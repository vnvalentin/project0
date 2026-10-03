import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock

from scripts import github_api_guard


class GitHubApiGuardTests(unittest.TestCase):
    def quota_result(self, remaining=5000, returncode=0, stderr=""):
        payload = {
            "graphql": {"limit": 5000, "remaining": remaining, "used": 5000 - remaining, "reset": 1234},
            "core": {"limit": 5000, "remaining": 4999, "used": 1, "reset": 1234},
        }
        return Mock(returncode=returncode, stdout=json.dumps(payload), stderr=stderr)

    def graphql_result(self, returncode=0, stdout=None, stderr=""):
        payload = {
            "data": {
                "rateLimit": {"limit": 5000, "remaining": 4999, "cost": 1, "resetAt": "2030-01-01T00:00:00Z"},
                "viewer": {"login": "test-user"},
            }
        }
        return Mock(returncode=returncode, stdout=json.dumps(payload) if stdout is None else stdout, stderr=stderr)

    def invoke(self, args, runner, directory):
        evidence = Path(directory) / "evidence.json"
        exit_code = github_api_guard.main(
            [args[0], "--evidence", str(evidence), *args[1:]], runner=runner
        )
        return exit_code, json.loads(evidence.read_text(encoding="utf-8"))

    def test_preflight_records_success_with_one_minimal_graphql_query(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = Mock(side_effect=[self.quota_result(), self.graphql_result()])
            exit_code, evidence = self.invoke(["preflight"], runner, directory)

        self.assertEqual(exit_code, 0)
        self.assertEqual(runner.call_count, 2)
        self.assertEqual(evidence["status"], "ready")
        self.assertEqual(evidence["quota"]["graphql"]["remaining"], 5000)
        self.assertEqual(evidence["graphql"]["rateLimit"]["cost"], 1)

    def test_preflight_skips_graphql_when_primary_budget_is_exhausted(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = Mock(return_value=self.quota_result(remaining=0))
            exit_code, evidence = self.invoke(["preflight"], runner, directory)

        self.assertNotEqual(exit_code, 0)
        self.assertEqual(runner.call_count, 1)
        self.assertEqual(evidence["status"], "blocked")
        self.assertEqual(evidence["reason"], "graphql_budget_exhausted")

    def test_preflight_preserves_graphql_error_despite_remaining_points_without_retry(self):
        failure = '{"errors":[{"type":"RATE_LIMIT","code":"graphql_rate_limit","message":"limit reached"}]}'
        with tempfile.TemporaryDirectory() as directory:
            runner = Mock(side_effect=[
                self.quota_result(remaining=4898),
                Mock(returncode=1, stdout=failure, stderr="GraphQL: API rate limit already exceeded"),
            ])
            exit_code, evidence = self.invoke(["preflight"], runner, directory)

        self.assertNotEqual(exit_code, 0)
        self.assertEqual(runner.call_count, 2)
        self.assertEqual(evidence["status"], "blocked")
        self.assertEqual(evidence["quota"]["graphql"]["remaining"], 4898)
        self.assertEqual(evidence["graphql"]["stderr"], "GraphQL: API rate limit already exceeded")
        self.assertEqual(evidence["graphql"]["response"], failure)

    def test_preflight_fails_closed_on_malformed_quota_without_graphql_call(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = Mock(return_value=Mock(returncode=0, stdout="not-json", stderr=""))
            exit_code, evidence = self.invoke(["preflight"], runner, directory)

        self.assertNotEqual(exit_code, 0)
        self.assertEqual(runner.call_count, 1)
        self.assertEqual(evidence["status"], "blocked")
        self.assertEqual(evidence["reason"], "invalid_quota_response")

    def test_preflight_fails_closed_on_malformed_graphql_response_without_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = Mock(side_effect=[
                self.quota_result(),
                Mock(returncode=0, stdout="not-json", stderr=""),
            ])
            exit_code, evidence = self.invoke(["preflight"], runner, directory)

        self.assertNotEqual(exit_code, 0)
        self.assertEqual(runner.call_count, 2)
        self.assertEqual(evidence["status"], "blocked")
        self.assertEqual(evidence["reason"], "graphql_preflight_failed")
        self.assertEqual(evidence["graphql"]["response"], "not-json")

    def test_project_cli_failure_runs_once_and_records_exact_error_and_quota(self):
        command = ["gh", "project", "field-list", "2", "--owner", "test-user"]
        with tempfile.TemporaryDirectory() as directory:
            runner = Mock(side_effect=[
                Mock(returncode=1, stdout="", stderr="API rate limit exceeded"),
                self.quota_result(remaining=4700),
            ])
            exit_code, evidence = self.invoke(["run", "--", *command], runner, directory)

        self.assertEqual(exit_code, 1)
        self.assertEqual(runner.call_count, 2)
        self.assertEqual(runner.call_args_list[0].args[0], command)
        self.assertEqual(evidence["status"], "failed")
        self.assertEqual(evidence["command_stderr"], "API rate limit exceeded")
        self.assertEqual(evidence["quota"]["graphql"]["remaining"], 4700)

    def test_project_cli_failure_is_not_hidden_when_quota_snapshot_fails(self):
        command = ["gh", "project", "view", "2", "--owner", "test-user"]
        with tempfile.TemporaryDirectory() as directory:
            runner = Mock(side_effect=[
                Mock(returncode=7, stdout="", stderr="project request failed"),
                Mock(returncode=1, stdout="", stderr="REST unavailable"),
            ])
            exit_code, evidence = self.invoke(["run", "--", *command], runner, directory)

        self.assertEqual(exit_code, 7)
        self.assertEqual(runner.call_count, 2)
        self.assertEqual(evidence["command_stderr"], "project request failed")
        self.assertEqual(evidence["quota_error"], "REST unavailable")

    def test_graphql_errors_with_success_exit_are_treated_as_failure(self):
        command = ["gh", "api", "graphql", "-f", "query=query { viewer { login } }"]
        response = '{"data":{"viewer":null},"errors":[{"message":"denied"}]}'
        with tempfile.TemporaryDirectory() as directory:
            runner = Mock(side_effect=[
                Mock(returncode=0, stdout=response, stderr=""),
                self.quota_result(remaining=4700),
            ])
            exit_code, evidence = self.invoke(["run", "--", *command], runner, directory)

        self.assertEqual(exit_code, 1)
        self.assertEqual(runner.call_count, 2)
        self.assertEqual(evidence["returncode"], 0)
        self.assertEqual(evidence["guard_exit_code"], 1)
        self.assertEqual(evidence["status"], "failed")
        self.assertEqual(evidence["reason"], "graphql_response_errors")
        self.assertEqual(evidence["command_response"], response)


if __name__ == "__main__":
    unittest.main()