"""Pure Python controls for the #1444 evidence validation seam."""

import argparse
import json
import os
from pathlib import Path
import unittest

from persistence_thread_affinity_evidence import validate_evidence


class PersistenceThreadAffinityControls(unittest.TestCase):
    def test_success_flag_cannot_qualify_missing_evidence(self):
        verdict = validate_evidence({"passed": True}, {}, b"", b"")
        self.assertFalse(verdict["passed"])
        self.assertEqual(verdict["coverage"], "NOT_OBSERVED")
        self.assertIn("schema", verdict["failure_codes"])

    def test_malformed_report_returns_closed_unqualified_result(self):
        for report in (None, [], True, 7, "untrusted-input-must-not-be-returned"):
            with self.subTest(kind=type(report).__name__):
                verdict = validate_evidence(report, {}, b"", b"")
                self.assertEqual(set(verdict), {"schema_version", "passed", "coverage",
                                                "failure_codes", "measurements"})
                self.assertFalse(verdict["passed"])
                self.assertEqual(verdict["failure_codes"], ["schema"])
                self.assertEqual(set(verdict["measurements"]),
                                 {"candidate", "main_sqlite_control", "main_wait_control"})
                self.assertTrue(all(value is None for mode in verdict["measurements"].values()
                                    for value in mode.values()))
                self.assertNotIn("untrusted-input", json.dumps(verdict))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(PersistenceThreadAffinityControls)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    receipt = {"schema_version": 1, "passed": result.wasSuccessful(),
               "tests_run": result.testsRun, "failures": len(result.failures),
               "errors": len(result.errors), "native_executed": False}
    descriptor = os.open(args.report, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        json.dump(receipt, stream, indent=2)
        stream.write("\n")
    return int(not result.wasSuccessful())


if __name__ == "__main__":
    raise SystemExit(main())
