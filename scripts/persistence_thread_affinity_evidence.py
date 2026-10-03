"""Fail-closed evidence validation for the bounded #1444 experiment.

A fixture success flag never establishes supported source or lifecycle coverage.
The complete receipt validator is built at this pure seam; no filesystem or
native execution belongs here.
"""


MODES = ("candidate", "main_sqlite_control", "main_wait_control")
MEASUREMENT_KEYS = ("known_native_entries", "known_main_native_entries",
                    "known_main_native_elapsed_usec", "known_worker_native_elapsed_usec",
                    "known_main_mailbox_elapsed_usec", "known_main_lock_call_elapsed_usec")


def validate_evidence(report: object, expected_manifest: object,
                      fixture_source_bytes: bytes,
                      public_test_source_bytes: bytes) -> dict[str, object]:
    missing_schema = (not isinstance(report, dict)
                      or type(report.get("schema_version")) is not int
                      or report.get("schema_version") != 1
                      or report.get("experiment") != "1444")
    return {"schema_version": 1, "passed": False, "coverage": "NOT_OBSERVED",
            "failure_codes": ["schema" if missing_schema else "incomplete_coverage"],
            "measurements": {mode: dict.fromkeys(MEASUREMENT_KEYS) for mode in MODES}}
