"""Public report seam: missing evidence never becomes a passing baseline."""
import json
from pathlib import Path
import unittest
from m4_baseline_report import evaluate, audit_worker_probe

class BaselineReportTests(unittest.TestCase):
    def test_empty_runtime_evidence_fails_closed(self):
        result = evaluate({}, True)
        self.assertFalse(result['passed'])
        self.assertIn('complete_tick_samples', result['failed_checks'])
        self.assertIn('isolation_observed', result['failed_checks'])

    def test_structural_probe_rejects_wait_added_to_measured_callback(self):
        source = Path('scripts/m4_load_server.gd').read_text()
        self.assertTrue(audit_worker_probe(source)['passed'])
        mutated = source.replace('func _m4_poll_workers() -> void:', 'func _m4_poll_workers() -> void:\n\tWorkerThreadPool.wait_for_task_completion(1)')
        self.assertFalse(audit_worker_probe(mutated)['passed'])

if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(BaselineReportTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    Path('build/validation').mkdir(parents=True, exist_ok=True)
    Path('build/validation/m4-report-tests.json').write_text(json.dumps({
        'tests': result.testsRun, 'failures': len(result.failures), 'errors': len(result.errors),
        'passed': result.wasSuccessful()}))
    raise SystemExit(not result.wasSuccessful())
