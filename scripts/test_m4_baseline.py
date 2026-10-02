"""Public report seam: missing evidence never becomes a passing baseline."""
import json
from pathlib import Path
import unittest
import subprocess
import sys
from run_m4_baseline import group_members, stop_owned_group, parse_arguments
from m4_baseline_report import evaluate, audit_worker_probe, summarize_stage_timings

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

    def test_incomplete_and_nonfinite_tick_data_never_passes(self):
        observation = {'configured_tick_rate': 30, 'elapsed_seconds': 1000 / 30,
                       'crossings': [{}] * 100, 'canon_reads': [{'duration_usec': 50, 'phase': 'readiness', 'context': 'boundary_lookup', 'outcome': 'ok', 'sector_id': 'sector-0-0'}], 'errors': [],
                       'body_activity': [{'steps': 1000, 'travel': 1.0} for _ in range(15)],
                       'entries_by_trigger': [1] * 15,
                       'background': {'accepted_connections': 4, 'results': [{'sector': 'sector-%d-10' % i, 'outcome': 'timeout'} for i in range(4)]},
                       'worker_probe': {'tasks': 32, 'completed_before_window_end': 32, 'peak_pending': 32, 'main_thread_id': 1, 'blocking_wait_calls_in_window': 0, 'blocking_wait_usec_in_window': 0, 'results': [{'thread_id': 2, 'iterations': 1} for _ in range(32)]},
                       'isolation': dict.fromkeys(('healthy_canon_unchanged', 'sector_fault_contained', 'background_contention_observed', 'structural_nonblocking_verified', 'lock_wait_observed'), True),
                       'samples': [{'tick': tick, 'duration_ms': 1.0, 'peers': 10, 'ready': 10, 'sectors': 4, 'npcs': 10, 'bodies': 15, 'triggers': 15} for tick in range(1000)]}
        self.assertTrue(evaluate(observation, True)['passed'])
        diagnostic = evaluate(observation, True, supported_load=True)
        self.assertFalse(diagnostic['passed'], 'explicit capacity measurement cannot imply isolation acceptance')
        self.assertTrue(diagnostic['checks']['complete_tick_samples'])
        self.assertEqual(diagnostic['p99_ms'], 1.0)
        observation['canon_reads'][0]['outcome'] = 'damaged'
        self.assertFalse(evaluate(observation, True)['passed'])
        observation['canon_reads'][0]['outcome'] = 'ok'
        observation['entries_by_trigger'][0] = 0
        self.assertFalse(evaluate(observation, True)['passed'])
        observation['entries_by_trigger'][0] = 1
        observation['body_activity'][0]['travel'] = 0
        self.assertFalse(evaluate(observation, True)['passed'])
        observation['body_activity'][0]['travel'] = 1.0
        observation['background']['results'][0]['outcome'] = 'unknown'
        self.assertFalse(evaluate(observation, True)['passed'])
        observation['background']['results'][0]['outcome'] = 'timeout'
        observation['worker_probe']['results'][0]['thread_id'] = 1
        self.assertFalse(evaluate(observation, True)['passed'])
        observation['worker_probe']['results'][0]['thread_id'] = 2
        observation['samples'][500]['duration_ms'] = float('nan')
        self.assertFalse(evaluate(observation, True)['passed'])
        observation['samples'][500]['duration_ms'] = 1.0
        observation['samples'][500]['tick'] = 499
        self.assertFalse(evaluate(observation, True)['passed'])
        observation['samples'][500]['tick'] = 500
        self.assertFalse(evaluate(observation, False)['passed'])
        observation['samples'].pop()
        self.assertFalse(evaluate(observation, True)['passed'])

    def test_stage_evidence_preserves_nested_times_and_refuses_missing_observations(self):
        sample = {'tick': 8, 'duration_ms': 20.0, 'physics_steps': 1,
                  'stage_timings': {
                      'server_physics_callback': {'calls': 1, 'duration_usec': 10000},
                      'player_position_callback': {'calls': 2, 'duration_usec': 5000},
                      'boundary_reentry_callback': {'calls': 0, 'duration_usec': 0},
                      'frontier_stay_callback': {'calls': 2, 'duration_usec': 500},
                      'journey_checkpoint': {'calls': 2, 'duration_usec': 4000}}}
        summary = summarize_stage_timings({'samples': [sample]})
        self.assertTrue(summary['qualified'])
        self.assertEqual(summary['peak_sample']['stage_timings']['journey_checkpoint']['duration_usec'], 4000)
        self.assertEqual(summary['stages']['server_physics_callback']['total_usec'], 10000)
        self.assertEqual(summary['stages']['player_position_callback']['total_usec'], 5000)
        self.assertNotIn('total_callback_usec', summary)  # Inclusive spans overlap.
        frontier = sample['stage_timings'].pop('frontier_stay_callback')
        self.assertFalse(summarize_stage_timings({'samples': [sample]})['qualified'])
        sample['stage_timings']['frontier_stay_callback'] = frontier
        del sample['stage_timings']['journey_checkpoint']
        self.assertFalse(summarize_stage_timings({'samples': [sample]})['qualified'])
        self.assertFalse(summarize_stage_timings({})['qualified'])

    def test_explicit_supported_load_preserves_default_stress_and_refuses_mixed_modes(self):
        image = ['--server-image', 'sha256:' + 'a' * 64]
        default = parse_arguments(image)
        self.assertEqual(default.worker_count, 32)
        self.assertFalse(default.supported_load)
        supported = parse_arguments(image + ['--ticks', '1000', '--supported-load'])
        self.assertEqual(supported.worker_count, 0)
        self.assertTrue(supported.supported_load)
        for options in (['--ticks', '60', '--supported-load'],
                        ['--supported-load', '--diagnostic-workers', '0'],
                        ['--ticks', '1000', '--diagnostic-workers', '0']):
            with self.subTest(options=options), self.assertRaises(SystemExit):
                parse_arguments(image + options)

    def test_owned_cleanup_removes_descendant_after_leader_exits(self):
        code = "import subprocess,sys; subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])"
        leader = subprocess.Popen([sys.executable, '-c', code], start_new_session=True,
                                  stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            leader.wait(timeout=3)
            self.assertTrue(group_members(leader.pid), 'surviving child is observed despite exited leader')
            self.assertTrue(stop_owned_group(leader))
            self.assertEqual(group_members(leader.pid), [])
        finally:
            stop_owned_group(leader)

if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(BaselineReportTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    Path('build/validation').mkdir(parents=True, exist_ok=True)
    Path('build/validation/m4-report-tests.json').write_text(json.dumps({
        'tests': result.testsRun, 'failures': len(result.failures), 'errors': len(result.errors),
        'passed': result.wasSuccessful()}))
    raise SystemExit(not result.wasSuccessful())
