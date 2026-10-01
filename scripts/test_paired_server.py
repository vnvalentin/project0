import copy
import json
import os
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import paired_server as harness


class PairedServerTests(unittest.TestCase):
    def test_shutdown_requires_verified_normal_termination(self):
        state = {"Running": False, "OOMKilled": False, "Error": "", "ExitCode": 143}
        self.assertTrue(harness.valid_shutdown(state, 0))
        self.assertTrue(harness.valid_shutdown(state | {"ExitCode": 0}, 0))
        self.assertFalse(harness.valid_shutdown(state, 1))
        for change in ({"Running": True}, {"OOMKilled": True}, {"Error": "daemon error"},
                       {"ExitCode": 137}, {"ExitCode": 1}):
            with self.subTest(change=change):
                self.assertFalse(harness.valid_shutdown(state | change, 0))

    def test_cleanup_requires_successful_absence_observation(self):
        for kind in ("container", "network"):
            with self.subTest(kind=kind):
                with patch.object(harness, "command", return_value=subprocess.CompletedProcess([], 1, "daemon unavailable")):
                    self.assertFalse(harness.remove_owned(kind, "owned-run", "run-1"))
                with patch.object(harness, "command", return_value=subprocess.CompletedProcess([], 0, "owned-run\n")):
                    self.assertFalse(harness.remove_owned(kind, "owned-run", "run-1"))
                with patch.object(harness, "command", return_value=subprocess.CompletedProcess([], 0, "")):
                    self.assertTrue(harness.remove_owned(kind, "owned-run", "run-1"))
                responses = [subprocess.CompletedProcess([], 0, "owned-run\n"),
                             subprocess.CompletedProcess([], 0, '{"project0.run":"different-run"}')]
                with patch.object(harness, "command", side_effect=responses) as commands:
                    self.assertFalse(harness.remove_owned(kind, "owned-run", "run-1"))
                    self.assertFalse(any("rm" in call.args for call in commands.call_args_list))
                responses = [subprocess.CompletedProcess([], 0, "owned-run\n"),
                             subprocess.CompletedProcess([], 0, '{"project0.run":"run-1"}'),
                             subprocess.CompletedProcess([], 0, "removed"),
                             subprocess.CompletedProcess([], 0, "")]
                with patch.object(harness, "command", side_effect=responses):
                    self.assertTrue(harness.remove_owned(kind, "owned-run", "run-1"))

    def test_finish_requires_fresh_current_admission(self):
        now = time.time()
        admission = {"authenticated": True, "input_ack_sequence": 3, "observed_at": now}
        self.assertTrue(harness.valid_admission(admission, 3, now - 1, now))
        for change in ({"authenticated": False}, {"input_ack_sequence": 2},
                       {"observed_at": now - 6}, {"observed_at": now + 1}):
            with self.subTest(change=change):
                self.assertFalse(harness.valid_admission(admission | change, 3, now - 1, now))

    def test_prepare_exports_committed_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "server").mkdir()
            (root / "scripts").mkdir()
            source = root / "server/server_main.gd"
            source.write_text("extends SceneTree\n")
            (root / "scripts/paired_server_fixture.gd").write_text("extends SceneTree\n")
            subprocess.run(["git", "-C", str(root), "init", "-q"], check=True)
            subprocess.run(["git", "-C", str(root), "add", "server", "scripts"], check=True)
            subprocess.run(["git", "-C", str(root), "-c", "user.name=fixture", "-c",
                            "user.email=fixture@invalid", "commit", "-qm", "fixture"], check=True)
            committed = source.read_bytes()
            source.write_text("uncommitted change\n")
            artifact = root / "artifact"
            harness.prepare(root, artifact)
            self.assertEqual((artifact / "server/server_main.gd").read_bytes(), committed)

    def test_wrong_host(self):
        with self.assertRaisesRegex(ValueError, "wrong_host"):
            harness.check_host("Windows", "not-okami")

    def test_artifact_hash_and_allowlist(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "server").mkdir()
            source = root / "server/server_main.gd"
            source.write_text("extends SceneTree\n")
            manifest = {"files": {"server/server_main.gd": harness.digest(source)}}
            harness.check_files(root, manifest)
            source.write_text("changed")
            with self.assertRaisesRegex(ValueError, "artifact_hash"):
                harness.check_files(root, manifest)
            with self.assertRaisesRegex(ValueError, "artifact_path"):
                harness.check_files(root, {"files": {"../secret": "0" * 64}})

    def test_occupied_endpoint(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as listener:
            listener.bind(("127.0.0.1", 0))
            with self.assertRaises(OSError):
                harness.reserve_port("127.0.0.1", listener.getsockname()[1])

    def test_client_evidence_identity_and_freshness(self):
        report = {
            "schema_version": 1, "run_id": "run-1", "scenario_id": harness.SCENARIO,
            "correlation_id": "correlation-1", "client_build": {"sha256": "a" * 64},
            "server_build": {"sha256": "b" * 64}, "started_at": time.time() - 2,
            "deadline_at": time.time() + 60,
        }
        evidence = {key: copy.deepcopy(report[key]) for key in harness.IDENTITY_KEYS}
        evidence.update(status="passed", observed_at=time.time(), authenticated=True,
                        world_entered=True, input_ack_sequence=1)
        harness.check_client(report, evidence)
        for key in harness.IDENTITY_KEYS:
            invalid = copy.deepcopy(evidence)
            invalid[key] = "wrong"
            with self.subTest(key=key), self.assertRaises(ValueError):
                harness.check_client(report, invalid)
        for change in [{"observed_at": 0}, {"authenticated": False},
                       {"status": "failed"}, {"input_ack_sequence": -1}]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                harness.check_client(report, evidence | change)

    def test_runtime_mismatch(self):
        manifest = {"image": harness.IMAGE, "server_engine": "4.3.stable.official.77dcf97d8"}
        harness.check_runtime(manifest)
        for change in ({"image": "wrong"}, {"server_engine": "4.7.2"}):
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, "incompatible_runtime"):
                harness.check_runtime(manifest | change)

    def test_redaction(self):
        token = "c2VjcmV0.c2lnbmF0dXJl"
        secret = "f" * 64
        sanitized = harness.redact(f"token={token} secret={secret}", [token, secret])
        self.assertNotIn(token, sanitized)
        self.assertNotIn(secret, sanitized)
        self.assertEqual(sanitized, "token=[REDACTED] secret=[REDACTED]")

    def test_shared_evidence_requires_movement_and_lifecycle(self):
        report = {"scenario_id": harness.SHARED_SCENARIO, "correlation_id": "run-1"}
        client_a = {"status": "passed", "scenario_id": harness.SHARED_SCENARIO,
                    "correlation_id": "run-1", "client_id": "a", "authenticated": True,
                    "world_entered": True, "character_id": "shared-run-1-a",
                    "client_build": {"sha256": "client"}, "server_build": {"sha256": "server"},
                    "remote_players": {"b": {"character_id": "shared-run-1-b", "position": [0.0, 1.0, 0.0]}},
                    "own_position": [0.0, 1.0, 1.0]}
        client_b = client_a | {"client_id": "b", "character_id": "shared-run-1-b",
                               "remote_players": {"a": {"character_id": "shared-run-1-a", "position": [0.0, 1.0, 0.0]}},
                               "own_position": [0.0, 1.0, -1.0]}
        observed_a = client_a | {"remote_players": {"b": {"character_id": "shared-run-1-b", "position": [0.0, 1.0, 1.0]}}}
        observed_b = client_b | {"remote_players": {"a": {"character_id": "shared-run-1-a", "position": [1.0, 1.0, 0.0]}}}
        report["client_build"] = {"sha256": "client"}
        report["server_build"] = {"sha256": "server"}
        evidence = {"scenario_id": harness.SHARED_SCENARIO, "correlation_id": "run-1",
                "clients": {"a": observed_a, "b": observed_b},
                    "phases": {"initial": {"a": client_a, "b": client_b,
                                               "baseline_a": [0.0, 1.0, 0.0],
                                               "baseline_b": [0.0, 1.0, 0.0]},
                                "disconnect": {"remote_players": {}},
                                "reconnect": client_a}}
        harness.check_shared_client(report, evidence)
        with self.assertRaisesRegex(ValueError, "shared_authoritative_movement"):
            harness.check_shared_client(report, evidence | {
                "clients": evidence["clients"] | {"a": observed_a | {"remote_players": {"b": {
                    "character_id": "shared-run-1-b", "position": [0.0, 1.0, 0.1]}}}}})

    def test_frontier_timeout_requires_forced_cutoff_frames_and_reentry(self):
        build = {"client_build": {"sha256": "client"}, "server_build": {"sha256": "server"}}
        report = {"scenario_id": harness.FRONTIER_TIMEOUT_SCENARIO, "correlation_id": "run-1"} | build
        frontier = {"sector_id": "sector-0--2", "geometry_ready": True, "crossed": True, "started_at_msec": 10,
                    "geometry_ready_at_msec": 3500, "crossed_at_msec": 3600, "ready_latency_ms": 3490,
                    "cross_latency_ms": 3590}
        client = {"status": "passed", "scenario_id": harness.FRONTIER_TIMEOUT_SCENARIO, "correlation_id": "run-1",
                  "authenticated": True, "world_entered": True, "frontier": frontier,
                  "frame_times": {"count": 200}, "reentry": {"left": True, "reentered": True}} | build
        evidence = {"scenario_id": harness.FRONTIER_TIMEOUT_SCENARIO, "correlation_id": "run-1", "client": client}
        self.assertTrue(harness.check_frontier_timeout_client(report, evidence))
        for change, reason in (({"frame_times": {"count": 0}}, "frame_samples"),
                               ({"reentry": {"left": True, "reentered": False}}, "reentry"),
                               ({"client_build": {"sha256": "other"}}, "build_identity"),
                               ({"status": "failed"}, "client_failed")):
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, reason):
                harness.check_frontier_timeout_client(report, evidence | {"client": client | change})
        observation = {"seeded": True, "authenticated_world_peers": 1, "canon_outcome": "ok",
                       "generation": {"request_outcome": "timeout", "fallback_selected": True},
                       "frontier_ready_events": [{"sector_id": "sector-0--2", "path": "generated"}]}
        self.assertTrue(harness.check_frontier_timeout_server(observation))
        for change, reason in (({"generation": {"request_outcome": "transport_error", "fallback_selected": True}}, "not_forced"),
                               ({"canon_outcome": "not_found"}, "canon"),
                               ({"frontier_ready_events": []}, "ready_record"),
                               ({"authenticated_world_peers": 2}, "server_peer")):
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, reason):
                harness.check_frontier_timeout_server(observation | change)

    def test_health_requires_progress_and_freshness(self):
        now = time.time()
        health = {"status": "healthy", "server_tick": 30, "timestamp": int(now)}
        self.assertTrue(harness.healthy(health, now, 29))
        self.assertFalse(harness.healthy(health, now, 30))
        self.assertFalse(harness.healthy(health | {"status": "starting"}, now, 29))
        self.assertFalse(harness.healthy(health | {"timestamp": 0}, now, 29))

    def test_partial_health_retains_snapshot_only_until_stale(self):
        now = time.time()
        previous = {"status": "healthy", "server_tick": 30, "timestamp": int(now)}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "health.json"
            path.write_text("{")
            observed = harness.read_health(path, previous)
            self.assertTrue(harness.healthy(observed, now, -1))
            self.assertFalse(harness.healthy(observed, now + 6, -1))
            path.write_text(json.dumps(previous | {"server_tick": 60}))
            self.assertEqual(harness.read_health(path, previous)["server_tick"], 60)


if os.environ.get("PAIRED_LIVE") == "1":
    class LiveLifecycleTests(unittest.TestCase):
        @classmethod
        def setUpClass(cls):
            harness.check_host()
            cls.artifact = Path(os.environ["PAIRED_ARTIFACT"]).resolve()
            cls.output = Path(os.environ["PAIRED_RESULTS"]).resolve()
            cls.output.mkdir(parents=True, exist_ok=False)
            cls.script = str(Path(harness.__file__).resolve())

        def launch(self, label, **overrides):
            run = self.output / label
            options = {"artifact": str(self.artifact), "artifact-sha256": harness.digest(self.artifact / "manifest.json"),
                       "run": str(run), "correlation-id": label,
                       "client-sha256": "0" * 64, "client-version": "0.14.14", "client-engine": "4.7.2",
                       "deadline-seconds": "35", "readiness-seconds": "25"} | overrides
            argv = [sys.executable, self.script, "start"]
            for key, value in options.items():
                argv.extend(["--" + key, str(value)])
            result = subprocess.run(argv, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.addCleanup(self.ensure_stopped, run)
            return run

        def wait(self, run, final=False):
            deadline = time.monotonic() + 55
            while time.monotonic() < deadline:
                report = harness.read_json(run / "report.json")
                if "finished_at" in report or (not final and report["status"] == "ready"):
                    return report
                time.sleep(0.1)
            self.fail("Supervisor exceeded bounded test deadline: " + str(run))

        def ensure_stopped(self, run):
            if "finished_at" not in harness.read_json(run / "report.json"):
                harness.write_json(run / "control.json", {"action": "abort"})
                self.wait(run, final=True)

        def assert_clean(self, report, reason):
            self.assertEqual(report["reason"], reason, report)
            self.assertTrue(report["cleanup"]["passed"], report)
            self.assertTrue(report["cleanup"]["private_state_removed"], report)
            self.assertFalse(report["paired_acceptance"])

        def test_real_readiness_abort_and_redaction(self):
            run = self.launch("ready-abort")
            ready = self.wait(run)
            self.assertEqual(ready["status"], "ready", ready)
            self.assertGreater(ready["readiness"]["storage"]["canon.db"]["rows"], 0)
            self.assertTrue(ready["readiness"]["auth"]["tampered_rejected"])
            status = harness.command(sys.executable, self.script, "status", "--run", str(run))
            self.assertFalse(json.loads(status.stdout)["admission"]["authenticated"])
            routes = harness.command("docker", "exec", ready["resources"]["container"], "cat", "/proc/net/route").stdout
            self.assertTrue(any(line.split()[1] == "00000000" for line in routes.splitlines()[1:]),
                            "Private server requires a return route to the Windows LAN client")
            token = (run / "private/assertion").read_text()
            self.assertEqual((run / "private/assertion").stat().st_mode & 0o777, 0o600)
            harness.write_json(run / "control.json", {"action": "abort"})
            final = self.wait(run, final=True)
            self.assert_clean(final, "aborted")
            self.assertEqual(final["runtime_error_lines"], 0, final)
            for path in run.iterdir():
                if path.is_file():
                    self.assertNotIn(token, path.read_text())

        def test_wrong_hash(self):
            run = self.launch("wrong-hash", **{"artifact-sha256": "f" * 64})
            self.assert_clean(self.wait(run, final=True), "artifact_manifest_hash")

        def test_missing_artifact(self):
            run = self.launch("missing-artifact", artifact=str(self.output / "absent"))
            final = self.wait(run, final=True)
            self.assertTrue(final["cleanup"]["passed"])
            self.assertEqual(final["status"], "failed")

        def test_occupied_target(self):
            run = self.launch("occupied-target")
            with self.assertRaises(FileExistsError):
                harness.start(argparse_namespace(run))
            self.ensure_stopped(run)

        def test_timeout(self):
            run = self.launch("timeout")
            self.assertEqual(self.wait(run)["status"], "ready")
            self.assert_clean(self.wait(run, final=True), "timeout")

        def test_cancel(self):
            run = self.launch("cancel")
            self.assertEqual(self.wait(run)["status"], "ready")
            os.kill(harness.read_json(run / "supervisor.json")["pid"], signal.SIGTERM)
            self.assert_clean(self.wait(run, final=True), "cancelled")

        def test_readiness_timeout(self):
            run = self.launch("readiness-timeout", **{"readiness-seconds": "1"})
            self.assert_clean(self.wait(run, final=True), "readiness_timeout")

        def test_false_client_pass_rejected(self):
            run = self.launch("false-client")
            ready = self.wait(run)
            self.assertEqual(ready["status"], "ready", ready)
            evidence = {key: ready[key] for key in harness.IDENTITY_KEYS}
            evidence.update(status="passed", observed_at=time.time(), authenticated=True,
                            world_entered=True, input_ack_sequence=0)
            harness.write_json(run / "control.json", {"action": "finish", "evidence": evidence})
            self.assert_clean(self.wait(run, final=True), "server_admission_missing")

        def test_client_mismatch_terminates(self):
            run = self.launch("client-mismatch")
            ready = self.wait(run)
            self.assertEqual(ready["status"], "ready", ready)
            evidence = {key: ready[key] for key in harness.IDENTITY_KEYS}
            evidence.update(status="passed", observed_at=time.time(), authenticated=True,
                            world_entered=True, input_ack_sequence=0, correlation_id="wrong")
            evidence_path = self.output / "mismatched-client.json"
            harness.write_json(evidence_path, evidence)
            result = subprocess.run([sys.executable, self.script, "finish", "--run", str(run),
                                     "--evidence", str(evidence_path)], capture_output=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assert_clean(self.wait(run, final=True), "client_evidence_rejected")


    def argparse_namespace(run):
        from argparse import Namespace
        return Namespace(run=run, correlation_id="occupied-target", client_sha256="0" * 64,
                         client_version="0.14.14", deadline_seconds=35, readiness_seconds=25)


if __name__ == "__main__":
    unittest.main()