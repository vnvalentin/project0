"""Pure Python controls for the #1444 evidence validation seam.

The hand-authored receipts are protocol controls, never native observations.
The source inputs are the two fixed public fixture files from this checkout.
"""

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import unittest

from persistence_thread_affinity_evidence import validate_evidence


MODES = ("candidate", "main_sqlite_control", "main_wait_control")
OPERATIONS = {
    "new": "sqlite.new", "identity": "object.get_instance_id", "path": "sqlite.path.set",
    "foreign_keys": "sqlite.foreign_keys.set", "read_only": "sqlite.read_only.set",
    "verbosity": "sqlite.verbosity_level.set", "open": "sqlite.open_db", "query": "sqlite.query",
    "bound_query": "sqlite.query_with_bindings", "rows": "sqlite.query_result.get",
    "autocommit": "sqlite.get_autocommit", "close": "sqlite.close_db", "weakref": "weakref.new",
    "release": "sqlite.release", "weakref_check": "weakref.get_ref",
}


def native_cycle(role: str, cycle: str, object_id: int, tick: int) -> tuple[dict, list[dict]]:
    # Independently authored public lifecycle expectations; do not import the
    # validator's private inventory or sequence builders to construct controls.
    actions = [(name, 1) for name in ("new", "identity", "path", "foreign_keys", "read_only", "verbosity", "open")]
    if cycle == "first":
        actions.extend([
            ("query", 1), ("rows", 1), ("query", 2), ("query", 3), ("rows", 2),
            ("query", 4), ("query", 5), ("rows", 3), ("query", 6), ("autocommit", 1),
            ("query", 7), ("autocommit", 2), ("bound_query", 1), ("query", 8), ("autocommit", 3),
            ("query", 9), ("autocommit", 4), ("bound_query", 2), ("query", 10), ("autocommit", 5),
            ("bound_query", 3), ("rows", 4), ("bound_query", 4), ("rows", 5),
        ])
        if role == "main_control":
            for index in range(32):
                actions.extend([("bound_query", index + 5), ("rows", index + 6)])
    else:
        actions.extend([
            ("query", 1), ("rows", 1), ("query", 2), ("rows", 2), ("query", 3), ("rows", 3),
            ("autocommit", 1), ("bound_query", 1), ("rows", 4), ("bound_query", 2), ("rows", 5),
        ])
    actions.extend([(name, 1) for name in ("close", "weakref", "release", "weakref_check")])
    caller = 202 if role == "worker" else 101
    spans = []
    for index, (name, ordinal) in enumerate(actions):
        outcome = ("null" if name == "weakref_check" else "released" if name == "release" else
                   "observed" if name in {"identity", "weakref", "rows", "autocommit"} else "ok")
        spans.append({"site": "native." + name, "operation": OPERATIONS[name], "phase": "request",
                      "cycle": cycle, "role": role, "ordinal": ordinal, "caller_begin": caller,
                      "caller_end": caller, "owner": caller, "object_begin": 0 if index < 2 else object_id,
                      "object_end": object_id, "begin_usec": tick + index * 2,
                      "end_usec": tick + index * 2 + 1, "outcome": outcome})
    summary = {"cycle": cycle, "success": True, "journal_mode_rows": [["wal"]],
               "foreign_keys_rows": [[1]], "user_version_rows": [[1444]], "committed_rows": [[7]],
               "rolled_back_rows": [], "control_rows": [[[7]] for _ in range(32)] if role == "main_control" else [],
               "autocommit_values": [1, 0, 1, 0, 1] if cycle == "first" else [1],
               "release": {"object_id": object_id, "weakref_null": True, "observed_caller": caller,
                           "tick_usec": spans[-1]["end_usec"]}}
    return summary, spans


def sync_span(site: str, operation: str, begin: int, *, end: int | None = None,
              phase: str = "request", role: str = "main", outcome: str = "ok",
              ordinal: int = 1) -> dict:
    kind = site.split(".")[1]
    object_id = {"mailbox": -1, "control": -2, "thread": -3}.get(kind, 0)
    caller = 101 if role == "main" else 202
    return {"site": site, "operation": operation, "phase": phase, "cycle": "none", "role": role,
            "ordinal": ordinal, "caller_begin": caller, "caller_end": caller, "owner": caller,
            "object_begin": 0 if site.endswith((".new", ".identity")) else object_id,
            "object_end": object_id, "begin_usec": begin, "end_usec": begin + 1 if end is None else end,
            "outcome": outcome}


def canonical_mode(name: str) -> dict:
    spans = []
    for index, kind in enumerate(("mailbox", "control", "thread")):
        spans.extend([
            sync_span(f"sync.{kind}.new", "thread.new" if kind == "thread" else "mutex.new", 1010 + index * 4, phase="init"),
            sync_span(f"sync.{kind}.identity", "object.get_instance_id", 1012 + index * 4, phase="init", outcome="observed"),
        ])
    spans.extend([
        sync_span("sync.thread.start", "thread.start", 1100, phase="init"),
        sync_span("sync.mailbox.main_try", "mutex.try_lock", 1300, phase="init", outcome="acquired"),
        sync_span("sync.mailbox.main_unlock", "mutex.unlock", 1302, phase="init"),
        sync_span("sync.mailbox.main_try", "mutex.try_lock", 2000, outcome="acquired"),
        sync_span("sync.mailbox.main_unlock", "mutex.unlock", 2002),
        sync_span("sync.mailbox.main_try", "mutex.try_lock", 3100, outcome="acquired"),
        sync_span("sync.mailbox.main_unlock", "mutex.unlock", 3102),
        sync_span("sync.thread.alive", "thread.is_alive", 3190, outcome="terminated"),
        sync_span("sync.thread.alive", "thread.is_alive", 3301, phase="teardown", outcome="terminated"),
        sync_span("sync.thread.join", "thread.wait_to_finish", 3303, phase="teardown"),
        sync_span("sync.thread.release", "thread.release", 3305, phase="teardown", outcome="released"),
        sync_span("sync.mailbox.release", "mutex.release", 3307, phase="teardown", outcome="released"),
        sync_span("sync.control.release", "mutex.release", 3309, phase="teardown", outcome="released"),
        sync_span("sync.mailbox.worker_lock", "mutex.lock", 1200, phase="init", role="worker"),
        sync_span("sync.mailbox.worker_unlock", "mutex.unlock", 1202, phase="init", role="worker"),
        sync_span("sync.mailbox.worker_lock", "mutex.lock", 2999, role="worker"),
        sync_span("sync.mailbox.worker_unlock", "mutex.unlock", 3002, role="worker"),
    ])
    first, first_spans = native_cycle("worker", "first", -10, 2500)
    reopen, reopen_spans = native_cycle("worker", "reopen", -11, 2700)
    lifecycles = [{"role": "worker", "success": True, "cycles": [first, reopen]}]
    spans.extend(first_spans + reopen_spans)
    if name == "main_sqlite_control":
        control, control_spans = native_cycle("main_control", "first", -12, 2100)
        lifecycles.append({"role": "main_control", "success": True, "cycles": [control]})
        spans.extend(control_spans)
    wait = {"armed_attempt": 0, "observation_attempt": 0, "state_before_sleeping": False,
            "state_after_sleeping": False, "futex_class": "NOT_OBSERVED", "observation_begin_usec": 0,
            "observation_end_usec": 0, "worker_unlock_begin_usec": 0, "source_attribution": "INFERENCE",
            "exact_target_identity": "NOT_OBSERVED", "continuous_wait_duration": "NOT_OBSERVED"}
    if name == "main_wait_control":
        spans.extend([
            sync_span("sync.control.worker_lock", "mutex.lock", 1150, phase="init", role="worker"),
            sync_span("sync.control.worker_unlock", "mutex.unlock", 2100, role="worker"),
            sync_span("sync.control.main_try", "mutex.try_lock", 2004, outcome="busy"),
            sync_span("sync.control.main_lock", "mutex.lock", 2006, end=2300),
            sync_span("sync.control.main_unlock", "mutex.unlock", 2301),
        ])
        wait.update({"armed_attempt": 1, "observation_attempt": 1, "state_before_sleeping": True,
                     "state_after_sleeping": True, "futex_class": "APPROVED_FUTEX_WAIT",
                     "observation_begin_usec": 2050, "observation_end_usec": 2051,
                     "worker_unlock_begin_usec": 2100, "failed_try_lock": True,
                     "main_lock_begin_usec": 2006, "main_lock_end_usec": 2300})
    return {"mode": name, "status": "complete", "failure_class": "none", "main_caller": 101, "worker_caller": 202,
            "window_begin_usec": 2000, "window_end_usec": 3201, "initialization_begin_usec": 1000,
            "initialization_end_usec": 1500, "termination_observed_usec": 3200, "worker_return_usec": 3010,
            "completion_published_usec": 3001, "teardown_begin_usec": 3300, "teardown_end_usec": 3350,
            "submitted_once": True, "result_consumed": True, "worker_terminated": True,
            "worker_joined": True, "owned_state_removed": True, "lifecycles": lifecycles, "spans": spans, "wait": wait}


def canonical_inputs() -> tuple[dict, dict, bytes, bytes]:
    root = Path(__file__).resolve().parents[1]
    fixture = (root / "tests/fixtures/persistence_thread_affinity_fixture.gd").read_bytes()
    public_test = (root / "tests/integration/test_persistence_thread_affinity.gd").read_bytes()
    manifest = {"schema_version": 1, "source_revision": "a" * 40,
                "source_hashes": {"fixture": hashlib.sha256(fixture).hexdigest(), "public_test": hashlib.sha256(public_test).hexdigest()},
                "expected_provenance": {"schema_version": 1, "member_sha256": {
                    "debug": "d380b79c56073f63e41593ddbe3460977bb42b1ee03dddd0a80d334a0f79187a",
                    "release": "09d73fac80382e172f4445b3da983e8db8e1317f0119188b99500832d660424a"},
                    "release_artifact_sha256": "639fd1c20ffaa8545f5341325eedfffa29fa3d8c3861c150aaacbc0478208ae3"}}
    report = {"schema_version": 1, "experiment": "1444", "modes": [canonical_mode(name) for name in MODES],
              "clock": {"units": "us", "samples_usec": list(range(1000, 1032))},
              "loaded_addon": {"selected_mode": "debug", "mapped_member_sha256": manifest["expected_provenance"]["member_sha256"]["debug"]},
              "source_fixture_sha256": manifest["source_hashes"]["fixture"],
              "limits": {"spans_per_mode": 256, "spans_total": 576, "mailbox_bytes": 65536,
                         "thread_return_bytes": 131072, "report_bytes": 262144, "proc_line_bytes": 8192, "proc_total_bytes": 1048576},
              "exact_target_futex_identity": "NOT_OBSERVED", "continuous_wait_duration": "NOT_OBSERVED", "production_acceptance": "NOT_OBSERVED"}
    return report, manifest, fixture, public_test


def find_span(mode: dict, site: str, *, role: str | None = None, cycle: str | None = None) -> dict:
    return next(span for span in mode["spans"] if span["site"] == site
                and (role is None or span["role"] == role) and (cycle is None or span["cycle"] == cycle))


class PersistenceThreadAffinityControls(unittest.TestCase):
    def assert_rejected(self, inputs: tuple, code: str) -> dict:
        verdict = validate_evidence(*inputs)
        self.assertFalse(verdict["passed"])
        self.assertEqual(verdict["coverage"], "NOT_OBSERVED")
        self.assertIn(code, verdict["failure_codes"])
        self.assertEqual(len(verdict["failure_codes"]), len(set(verdict["failure_codes"])))
        self.assertLessEqual(len(verdict["failure_codes"]), 15)
        self.assertTrue(all(value is None or type(value) is int and 0 <= value <= (1 << 63) - 1
                            for mode in verdict["measurements"].values() for value in mode.values()))
        return verdict

    def test_success_flag_cannot_qualify_missing_evidence(self):
        verdict = validate_evidence({"passed": True}, {}, b"", b"")
        self.assertFalse(verdict["passed"])
        self.assertEqual(verdict["coverage"], "NOT_OBSERVED")
        self.assertIn("schema", verdict["failure_codes"])

    def test_malformed_report_returns_closed_unqualified_result(self):
        for report in (None, [], True, 7, "untrusted-input-must-not-be-returned"):
            with self.subTest(kind=type(report).__name__):
                verdict = validate_evidence(report, {}, b"", b"")
                self.assertEqual(set(verdict), {"schema_version", "passed", "coverage", "failure_codes", "measurements"})
                self.assertFalse(verdict["passed"])
                self.assertEqual(verdict["failure_codes"], ["schema"])
                self.assertTrue(all(value is None for mode in verdict["measurements"].values() for value in mode.values()))
                self.assertNotIn("untrusted-input", json.dumps(verdict))

    def test_complete_source_bound_receipt_derives_honest_measurements(self):
        verdict = validate_evidence(*canonical_inputs())
        self.assertTrue(verdict["passed"], verdict["failure_codes"])
        self.assertEqual(verdict["coverage"], "QUALIFIED")
        self.assertEqual(verdict["failure_codes"], [])
        candidate = verdict["measurements"]["candidate"]
        self.assertEqual(candidate, {"known_native_entries": 51, "known_main_native_entries": 0,
                                     "known_main_native_elapsed_usec": 0, "known_worker_native_elapsed_usec": 51,
                                     "known_main_mailbox_elapsed_usec": 4, "known_main_lock_call_elapsed_usec": 0})
        control = verdict["measurements"]["main_sqlite_control"]
        self.assertEqual(control["known_native_entries"], 147)
        self.assertEqual(control["known_main_native_entries"], 96)
        self.assertEqual(control["known_main_native_elapsed_usec"], 96)
        self.assertEqual(verdict["measurements"]["main_wait_control"]["known_main_lock_call_elapsed_usec"], 294)

    def test_missing_or_wrong_native_boundary_never_becomes_zero(self):
        for site in ("native.new", "native.identity", "native.path", "native.foreign_keys", "native.read_only",
                     "native.verbosity", "native.open", "native.query", "native.bound_query", "native.rows",
                     "native.autocommit", "native.close", "native.weakref", "native.release", "native.weakref_check"):
            with self.subTest(site=site):
                inputs = canonical_inputs()
                mode = inputs[0]["modes"][0]
                mode["spans"].remove(find_span(mode, site, role="worker", cycle="first"))
                self.assert_rejected(inputs, "span_coverage")
        for key in ("caller_end", "object_end", "end_usec", "operation"):
            with self.subTest(missing_field=key):
                inputs = canonical_inputs()
                del find_span(inputs[0]["modes"][0], "native.close")[key]
                self.assert_rejected(inputs, "span_coverage")

    def test_native_sequence_owner_and_final_reference_are_independent_requirements(self):
        for key, value, code in (("caller_end", 303, "caller_owner"), ("owner", 303, "caller_owner"),
                                 ("object_end", -99, "object_lifecycle"), ("object_begin", 0, "object_lifecycle"),
                                 ("ordinal", 9, "span_coverage"), ("outcome", "failed", "span_coverage")):
            with self.subTest(field=key):
                inputs = canonical_inputs()
                find_span(inputs[0]["modes"][0], "native.close")[key] = value
                self.assert_rejected(inputs, code)
        for field, value in (("weakref_null", False), ("object_id", -99), ("observed_caller", 303), ("tick_usec", 1)):
            with self.subTest(release=field):
                inputs = canonical_inputs()
                inputs[0]["modes"][0]["lifecycles"][0]["cycles"][0]["release"][field] = value
                self.assert_rejected(inputs, "object_lifecycle")
        inputs = canonical_inputs()
        mode = inputs[0]["modes"][0]
        mode["lifecycles"][0]["cycles"].pop()
        self.assert_rejected(inputs, "object_lifecycle")

    def test_commit_rollback_reopen_and_metadata_use_typed_actual_rows(self):
        for cycle in (0, 1):
            for field, value in (("journal_mode_rows", [["delete"]]), ("foreign_keys_rows", [[True]]),
                                 ("user_version_rows", [[1]]), ("committed_rows", [[8]]),
                                 ("rolled_back_rows", [[11]]), ("autocommit_values", [True])):
                with self.subTest(cycle=cycle, field=field):
                    inputs = canonical_inputs()
                    inputs[0]["modes"][0]["lifecycles"][0]["cycles"][cycle][field] = value
                    self.assert_rejected(inputs, "parity")
        inputs = canonical_inputs()
        inputs[0]["modes"][1]["lifecycles"][1]["cycles"][0]["control_rows"].pop()
        self.assert_rejected(inputs, "parity")

    def test_equal_tick_main_native_and_blocking_entries_are_forbidden(self):
        inputs = canonical_inputs()
        span = find_span(inputs[0]["modes"][0], "native.open")
        span.update({"caller_begin": 101, "caller_end": 101, "owner": 101, "end_usec": span["begin_usec"]})
        verdict = self.assert_rejected(inputs, "forbidden_main_entry")
        self.assertEqual(verdict["measurements"]["candidate"]["known_main_native_entries"], 1)
        self.assertEqual(verdict["measurements"]["candidate"]["known_main_native_elapsed_usec"], 0)
        inputs = canonical_inputs()
        inputs[0]["modes"][0]["spans"].append(sync_span("sync.control.main_lock", "mutex.lock", 2006, end=2006))
        self.assert_rejected(inputs, "forbidden_main_entry")

    def test_controls_require_positive_raw_work_and_actual_corroborated_contention(self):
        inputs = canonical_inputs()
        for span in inputs[0]["modes"][1]["spans"]:
            if span["role"] == "main_control":
                span["end_usec"] = span["begin_usec"]
        self.assert_rejected(inputs, "control_ineffective")
        for field, value in (("failed_try_lock", False), ("armed_attempt", 0), ("observation_attempt", 0),
                             ("state_before_sleeping", False), ("state_after_sleeping", False),
                             ("futex_class", "NOT_OBSERVED"), ("observation_end_usec", 2100),
                             ("source_attribution", "PROVEN"), ("exact_target_identity", "PROVEN"),
                             ("continuous_wait_duration", "PROVEN")):
            with self.subTest(wait_field=field):
                inputs = canonical_inputs()
                inputs[0]["modes"][2]["wait"][field] = value
                self.assert_rejected(inputs, "control_ineffective")

    def test_clock_unknown_or_backward_elapsed_is_not_a_zero_measurement(self):
        for samples in ([1000] * 32, list(reversed(range(1000, 1032))), [True] * 32, [-1] * 32):
            inputs = canonical_inputs()
            inputs[0]["clock"]["samples_usec"] = samples
            self.assert_rejected(inputs, "clock")
        inputs = canonical_inputs()
        span = find_span(inputs[0]["modes"][0], "native.query")
        span["end_usec"] = span["begin_usec"] - 1
        verdict = self.assert_rejected(inputs, "clock")
        self.assertIsNone(verdict["measurements"]["candidate"]["known_worker_native_elapsed_usec"])

    def test_source_hashes_and_official_member_association_are_required(self):
        inputs = canonical_inputs()
        inputs[1]["source_hashes"]["fixture"] = "0" * 64
        self.assert_rejected(inputs, "source_binding")
        for field, value in (("selected_mode", "NOT_OBSERVED"), ("selected_mode", "release"),
                             ("mapped_member_sha256", "0" * 64)):
            inputs = canonical_inputs()
            inputs[0]["loaded_addon"][field] = value
            self.assert_rejected(inputs, "provenance")
        inputs = canonical_inputs()
        inputs[1]["expected_provenance"]["release_artifact_sha256"] = "0" * 64
        self.assert_rejected(inputs, "provenance")

    def test_unqualified_source_or_provenance_yields_no_numeric_measurements(self):
        for kind in ("source_binding", "source_inventory", "provenance"):
            with self.subTest(upstream=kind):
                inputs = list(canonical_inputs())
                if kind == "source_binding":
                    inputs[1]["source_hashes"]["fixture"] = "0" * 64
                elif kind == "source_inventory":
                    inputs[2] += b"\ndatabase.query(\"untraced\")\n"
                    digest = hashlib.sha256(inputs[2]).hexdigest()
                    inputs[1]["source_hashes"]["fixture"] = digest
                    inputs[0]["source_fixture_sha256"] = digest
                else:
                    inputs[0]["loaded_addon"]["mapped_member_sha256"] = "0" * 64
                verdict = self.assert_rejected(tuple(inputs), kind)
                self.assertTrue(all(number is None for row in verdict["measurements"].values() for number in row.values()))

    def test_rehashed_source_with_untraced_native_or_blocking_calls_still_fails(self):
        for target, suffix in ((2, b"\ndatabase.query(\"untraced\")\n"), (2, b"\n_control.lock()\n"),
                               (2, b"\nvar alias: SQLite = database\n"), (3, b"\nOS.delay_usec(1)\n"),
                               (3, b'\nfixture.call("unapproved_method")\n')):
            with self.subTest(target=target, suffix=suffix):
                inputs = list(canonical_inputs())
                inputs[target] += suffix
                name = "fixture" if target == 2 else "public_test"
                inputs[1]["source_hashes"][name] = hashlib.sha256(inputs[target]).hexdigest()
                inputs[0]["source_fixture_sha256"] = inputs[1]["source_hashes"]["fixture"]
                self.assert_rejected(tuple(inputs), "source_inventory")
        for before, after in ((b"# AFFINITY_SITE native.close sqlite.close_db", b"# absent boundary"),
                              (b"var closed: bool = database.close_db()", b"var closed: bool = true"),
                              (b'_end(span, events, object_id, "observed")', b"pass")):
            inputs = list(canonical_inputs())
            self.assertIn(before, inputs[2])
            inputs[2] = inputs[2].replace(before, after, 1)
            inputs[1]["source_hashes"]["fixture"] = hashlib.sha256(inputs[2]).hexdigest()
            inputs[0]["source_fixture_sha256"] = inputs[1]["source_hashes"]["fixture"]
            self.assert_rejected(tuple(inputs), "source_inventory")

    def test_full_stat_tail_or_extra_call_in_direct_lock_interval_fails_source_qualification(self):
        inputs = list(canonical_inputs())
        start = inputs[2].index(b"func _read_state(")
        end = inputs[2].index(b"\n\nfunc _native_cleanup_known", start)
        old_reader = b'''func _read_state(path: String) -> String:
\tvar prefix: String = _read_prefix(path, 4096)
\tvar boundary: int = prefix.rfind(") ")
\treturn prefix.substr(boundary + 2, 1)
'''
        inputs[2] = inputs[2][:start] + old_reader + inputs[2][end:]
        inputs[1]["source_hashes"]["fixture"] = hashlib.sha256(inputs[2]).hexdigest()
        inputs[0]["source_fixture_sha256"] = inputs[1]["source_hashes"]["fixture"]
        self.assert_rejected(tuple(inputs), "source_inventory")
        for before, after in ((b"var separator: int = stream.get_8()", b"var separator: int = stream.get_buffer(4096).size()"),
                              (b'const MAIN_COMM: String = "godot"', b'const MAIN_COMM: String = "unknown"'),
                              (b"lock_begin = Time.get_ticks_usec()", b"lock_begin = Time.get_ticks_usec()\n\tOS.get_thread_caller_id()")):
            inputs = list(canonical_inputs())
            self.assertIn(before, inputs[2])
            inputs[2] = inputs[2].replace(before, after, 1)
            inputs[1]["source_hashes"]["fixture"] = hashlib.sha256(inputs[2]).hexdigest()
            inputs[0]["source_fixture_sha256"] = inputs[1]["source_hashes"]["fixture"]
            self.assert_rejected(tuple(inputs), "source_inventory")

    def test_join_cleanup_and_publication_order_are_not_success_flags(self):
        for field in ("worker_joined", "owned_state_removed", "result_consumed", "worker_terminated", "submitted_once"):
            inputs = canonical_inputs()
            inputs[0]["modes"][0][field] = False
            self.assert_rejected(inputs, "cleanup")
        for field, tick in (("completion_published_usec", 2100), ("worker_return_usec", 3000),
                            ("termination_observed_usec", 3009), ("teardown_begin_usec", 3200)):
            inputs = canonical_inputs()
            inputs[0]["modes"][0][field] = tick
            self.assert_rejected(inputs, "chronology")
        inputs = canonical_inputs()
        find_span(inputs[0]["modes"][0], "sync.thread.join")["phase"] = "request"
        self.assert_rejected(inputs, "forbidden_main_entry")

    def test_closed_modes_limits_and_overflow_cannot_be_waived(self):
        for key in ("spans_per_mode", "spans_total", "mailbox_bytes", "thread_return_bytes", "report_bytes", "proc_line_bytes", "proc_total_bytes"):
            inputs = canonical_inputs()
            inputs[0]["limits"][key] += 1
            self.assert_rejected(inputs, "bounds")
        for mutation in (lambda modes: modes.pop(), lambda modes: modes.append(copy.deepcopy(modes[0])),
                         lambda modes: modes.__setitem__(1, copy.deepcopy(modes[0]))):
            inputs = canonical_inputs()
            mutation(inputs[0]["modes"])
            self.assertFalse(validate_evidence(*inputs)["passed"])
        inputs = canonical_inputs()
        inputs[0]["modes"][0]["spans"] = [{"site": "trace_overflow"}]
        self.assert_rejected(inputs, "span_coverage")
        inputs = canonical_inputs()
        inputs[0]["modes"][0]["spans"] = [copy.deepcopy(inputs[0]["modes"][0]["spans"][0])] * 257
        self.assert_rejected(inputs, "bounds")

    def test_unknown_nested_text_is_not_returned_by_failed_verdict(self):
        inputs = canonical_inputs()
        inputs[0]["modes"][0]["failure_class"] = "private-input-must-not-escape"
        verdict = self.assert_rejected(inputs, "mode_coverage")
        self.assertNotIn("private-input", json.dumps(verdict))

    def test_aggregate_and_serialized_channel_caps_are_actual_bounds(self):
        inputs = canonical_inputs()
        for mode in inputs[0]["modes"]:
            mode["spans"] = [copy.deepcopy(mode["spans"][0])] * 200
        self.assertEqual(sum(len(mode["spans"]) for mode in inputs[0]["modes"]), 600)
        self.assert_rejected(inputs, "bounds")
        inputs = canonical_inputs()
        for mode in inputs[0]["modes"]:
            large = copy.deepcopy(mode["spans"][0])
            for key in ("site", "operation", "phase", "cycle", "role", "outcome"):
                large[key] = "x" * 128
            mode["spans"] = [large] * 192
        self.assertEqual(sum(len(mode["spans"]) for mode in inputs[0]["modes"]), 576)
        self.assertGreater(len(json.dumps(inputs[0], separators=(",", ":")).encode()), 262144)
        self.assert_rejected(inputs, "bounds")
        inputs = canonical_inputs()
        mode = inputs[0]["modes"][0]
        while len(mode["spans"]) < 256:
            mode["spans"].append(sync_span("sync.worker_delay", "os.delay_usec", 1400, phase="init", role="worker"))
        for cycle in mode["lifecycles"][0]["cycles"]:
            cycle["control_rows"] = [[["x" * 128]] for _ in range(256)]
        self.assertLessEqual(len(json.dumps(inputs[0], separators=(",", ":")).encode()), 262144)
        self.assertLessEqual(sum(len(item["spans"]) for item in inputs[0]["modes"]), 576)
        self.assert_rejected(inputs, "bounds")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(PersistenceThreadAffinityControls)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    receipt = {"schema_version": 1, "passed": result.wasSuccessful(), "tests_run": result.testsRun,
               "failures": len(result.failures), "errors": len(result.errors), "native_executed": False}
    descriptor = os.open(args.report, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        json.dump(receipt, stream, indent=2)
        stream.write("\n")
    return int(not result.wasSuccessful())


if __name__ == "__main__":
    raise SystemExit(main())
