"""Public report seam: missing evidence never becomes a passing baseline."""
import json
from pathlib import Path
import unittest
from m4_baseline_report import evaluate

class BaselineReportTests(unittest.TestCase):
    def test_empty_runtime_evidence_fails_closed(self):
        result = evaluate({}, True)
        self.assertFalse(result['passed'])
        self.assertIn('complete_tick_samples', result['failed_checks'])
        self.assertIn('isolation_observed', result['failed_checks'])

if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(BaselineReportTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    Path('build/validation').mkdir(parents=True, exist_ok=True)
    Path('build/validation/m4-report-tests.json').write_text(json.dumps({
        'tests': result.testsRun, 'failures': len(result.failures), 'errors': len(result.errors),
        'passed': result.wasSuccessful()}))
    raise SystemExit(not result.wasSuccessful())
