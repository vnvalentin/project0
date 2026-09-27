import argparse
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]


class AdmissionTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location("admission", ROOT / "scripts/ci_runner_admission.py")
        self.admission = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.admission)
        self.context = {
            "GITHUB_REPOSITORY": "vnvalentin/project0",
            "GITHUB_EVENT_NAME": "pull_request",
            "GITHUB_SHA": "a" * 40,
            "GITHUB_REF": "refs/pull/1265/merge",
            "GITHUB_WORKFLOW_REF": "vnvalentin/project0/.github/workflows/validation.yml@refs/pull/1265/merge",
            "GITHUB_WORKFLOW_SHA": "a" * 40,
            "GITHUB_JOB": "godot",
            "RUNNER_NAME": "okami",
            "CANDIDATE_REPOSITORY": "vnvalentin/project0",
            "CANDIDATE_SHA": "a" * 40,
            "WINDOWS_REQUIRED": False,
        }
        self.approval = {
            "event": "pull_request", "sha": "a" * 40, "ref": "refs/pull/1265/merge",
            "workflow_ref": self.context["GITHUB_WORKFLOW_REF"], "workflow_sha": "a" * 40,
            "jobs": ["ownership", "godot", "records", "python"],
            "expires_at": 2000, "source_ref": "a" * 40, "source_tree": "b" * 40,
            "platform": "linux", "windows_required": False,
            "candidate_sha": "a" * 40,
            "contract": "direct-source", "approval_issue": 1265,
            "required_checks": ["Validation ownership and client boundary", "Godot GUT suite",
                                "Delivery record sync", "Python service tests", "Windows launcher tests",
                                "project0-godot", "project0-infra", "project0-dashboard"],
        }
        self.policy = {"schema_version": 1, "repository": "vnvalentin/project0", "runner": "okami",
                       "approvals": [self.approval]}

    def test_independently_approved_exact_linux_source_is_allowed(self):
        self.assertTrue(self.admission.decide(self.policy, self.context, 1000)["allowed"])

    def test_candidate_cannot_mint_its_own_approval(self):
        context = copy.deepcopy(self.context)
        context["claimed_approved"] = True
        context["linux_ref"] = "a" * 40
        policy = copy.deepcopy(self.policy)
        policy["approvals"] = []
        self.assertFalse(self.admission.decide(policy, context, 1000)["allowed"])

    def test_windows_candidate_allows_only_independently_bound_linux_baseline(self):
        self.context["WINDOWS_REQUIRED"] = True
        self.approval.update({"contract": "approved-ref", "windows_required": True,
                              "source_ref": "c" * 40, "baseline_ref": "c" * 40,
                              "authority_ref": "c" * 40, "linux_input_digest": "d" * 64,
                              "candidate_linux_input_digest": "d" * 64,
                              "image_publication": False})
        result = self.admission.decide(self.policy, self.context, 1000)
        self.assertTrue(result["allowed"])
        self.assertEqual(result["source_ref"], "c" * 40)
        for field, value in [("source_ref", "a" * 40), ("authority_ref", "e" * 40),
                             ("candidate_linux_input_digest", "f" * 64), ("image_publication", True)]:
            with self.subTest(field=field):
                policy = copy.deepcopy(self.policy)
                policy["approvals"][0][field] = value
                self.assertFalse(self.admission.decide(policy, self.context, 1000)["allowed"])

            context = self.context | {"CANDIDATE_SHA": "e" * 40}
            policy = copy.deepcopy(self.policy)
            policy["approvals"][0].update({"candidate_sha": "e" * 40, "source_ref": "e" * 40,
                               "baseline_ref": "e" * 40, "authority_ref": "e" * 40})
            self.assertFalse(self.admission.decide(policy, context, 1000)["allowed"])

    def test_foreign_candidate_cannot_use_target_repository_approval(self):
        context = self.context | {"CANDIDATE_REPOSITORY": "foreign/project0"}
        self.assertFalse(self.admission.decide(self.policy, context, 1000)["allowed"])

    def test_reviewed_head_can_be_selected_from_its_pr_merge_context(self):
        self.context["CANDIDATE_SHA"] = "c" * 40
        self.approval.update({"candidate_sha": "c" * 40, "source_ref": "c" * 40})
        result = self.admission.decide(self.policy, self.context, 1000)
        self.assertTrue(result["allowed"])
        self.assertEqual(result["source_ref"], "c" * 40)

    def test_candidate_writable_policy_cannot_authorize_cli(self):
        policy = copy.deepcopy(self.policy)
        policy["approvals"][0]["expires_at"] = int(time.time()) + 600
        with tempfile.TemporaryDirectory() as temporary:
            policy_path = Path(temporary) / "policy.json"
            policy_path.write_text(json.dumps(policy))
            result = subprocess.run([sys.executable, str(ROOT / "scripts/ci_runner_admission.py"),
                                     "--policy", str(policy_path)],
                                    env=os.environ | {name: self.context.get(name, "") for name in self.admission.CONTEXT_FIELDS},
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 1)
            self.assertFalse(json.loads(result.stdout)["allowed"])

    def test_changed_identity_workflow_host_and_job_are_denied(self):
        for field in self.context:
            with self.subTest(field=field):
                context = self.context | {field: "forged"}
                self.assertFalse(self.admission.decide(self.policy, context, 1000)["allowed"])

    def test_expired_ambiguous_and_incomplete_approvals_are_denied(self):
        for field, value in [("expires_at", 1000), ("expires_at", True), ("approval_issue", True),
                             ("platform", "windows"), ("windows_required", True),
                             ("source_ref", "c" * 40), ("source_tree", "unknown"),
                             ("jobs", []), ("required_checks", []), ("contract", "candidate-plan")]:
            with self.subTest(field=field):
                policy = copy.deepcopy(self.policy)
                policy["approvals"][0][field] = value
                self.assertFalse(self.admission.decide(policy, self.context, 1000)["allowed"])
        policy = copy.deepcopy(self.policy)
        policy["approvals"].append(copy.deepcopy(self.approval))
        self.assertFalse(self.admission.decide(policy, self.context, 1000)["allowed"])

    def test_manual_and_tag_sources_require_independent_main_history_approval(self):
        for event, ref in [("workflow_dispatch", "refs/heads/main"), ("push", "refs/tags/v1.0.0")]:
            with self.subTest(event=event):
                context = self.context | {"GITHUB_EVENT_NAME": event, "GITHUB_REF": ref,
                                          "GITHUB_WORKFLOW_REF": "vnvalentin/project0/.github/workflows/images.yml@" + ref}
                policy = copy.deepcopy(self.policy)
                policy["approvals"][0].update({"event": event, "ref": ref, "workflow_ref": context["GITHUB_WORKFLOW_REF"]})
                self.assertFalse(self.admission.decide(policy, context, 1000)["allowed"])
                policy["approvals"][0]["approved_main_sha"] = "a" * 40
                self.assertTrue(self.admission.decide(policy, context, 1000)["allowed"])
                policy["approvals"][0]["windows_required"] = True
                self.assertFalse(self.admission.decide(policy, context, 1000)["allowed"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(AdmissionTests))
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps({"passed": result.wasSuccessful(), "tests": result.testsRun,
                                      "failures": len(result.failures), "errors": len(result.errors),
                                      "skipped": len(result.skipped)}, indent=2) + "\n")
    raise SystemExit(not result.wasSuccessful())