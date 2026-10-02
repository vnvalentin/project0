"""M4 acceptance evaluator. It consumes observations, never supplies missing ones."""
import math


def evaluate(observation: dict, cleanup: bool, supported_load: bool = False) -> dict:
    samples = observation.get('samples', [])
    complete = len(samples) == 1000 and all(isinstance(s, dict) for s in samples)
    ticks = [s.get('tick') for s in samples] if complete else []
    complete = complete and all(isinstance(t, int) for t in ticks)
    complete = complete and ticks == list(range(ticks[0], ticks[0] + 1000)) if ticks else False
    durations = [s.get('duration_ms') for s in samples] if complete else []
    finite = bool(durations) and all(isinstance(v, (int, float)) and math.isfinite(v) and v >= 0 for v in durations)
    ordered = sorted(durations) if finite else []
    elapsed = observation.get('elapsed_seconds', 0)
    elapsed_valid = isinstance(elapsed, (int, float)) and math.isfinite(elapsed) and elapsed > 0
    crossings = observation.get('crossings', [])
    isolation = observation.get('isolation', {})
    bodies = observation.get('body_activity', [])
    entries = observation.get('entries_by_trigger', [])
    background = observation.get('background', {})
    results = background.get('results', [])
    worker = observation.get('worker_probe', {})
    worker_results = worker.get('results', [])
    checks = {
        'complete_tick_samples': complete,
        'finite_durations': finite,
        '30hz': observation.get('configured_tick_rate') == 30,
        'full_workload_each_tick': complete and all(s.get('peers') == 10 and s.get('ready') == 10 and s.get('sectors', 0) >= 4 and s.get('npcs', 0) >= 10 and s.get('bodies', 0) >= 15 and s.get('triggers', 0) >= 15 for s in samples),
        'p99_at_most_33_3ms': bool(ordered) and ordered[989] <= 33.3,
        'max_at_most_50ms': bool(ordered) and ordered[-1] <= 50,
        'crossings_at_least_two_per_second': elapsed_valid and len(crossings) / elapsed >= 2,
        'canon_timing_observed': any(r.get('outcome') == 'ok' and r.get('sector_id') in ('sector-0-0', 'sector-1-0', 'sector-0-1', 'sector-1-1') and r.get('phase') in ('setup', 'readiness', 'measured') and isinstance(r.get('duration_usec'), (int, float)) and math.isfinite(r['duration_usec']) and r['duration_usec'] >= 0 for r in observation.get('canon_reads', [])),
        'isolation_observed': all(isolation.get(k) is True for k in ('healthy_canon_unchanged', 'sector_fault_contained', 'background_contention_observed', 'structural_nonblocking_verified', 'lock_wait_observed')),
        'dynamic_activity_observed': len(bodies) == 15 and all(isinstance(b, dict) and isinstance(b.get('travel'), (int, float)) and math.isfinite(b['travel']) and b['travel'] > 0 and b.get('steps', 0) >= len(samples) for b in bodies) and len(entries) == 15 and all(isinstance(n, int) and n > 0 for n in entries),
        'background_outcomes_observed': background.get('accepted_connections') == 4 and len(results) == 4 and {r.get('sector') for r in results} == {'sector-%d-10' % i for i in range(4)} and all(r.get('outcome') == 'timeout' for r in results),
        'worker_activity_observed': worker.get('tasks') == 32 and worker.get('completed_before_window_end') == 32 and worker.get('peak_pending', 0) > 0 and worker.get('blocking_wait_calls_in_window') == 0 and worker.get('blocking_wait_usec_in_window') == 0 and len(worker_results) == 32 and all(r.get('iterations', 0) > 0 and r.get('thread_id') != worker.get('main_thread_id') for r in worker_results),
        'runtime_errors_absent': observation.get('errors') == [],
        'callback_stage_evidence_qualified': summarize_stage_timings(observation)['qualified'],
        'cleanup_verified': cleanup is True,
    }
    return {'passed': all(checks.values()) and not supported_load, 'checks': checks,
            'acceptance_exclusions': ['supported_load_requires_independent_contention_isolation'] if supported_load else [],
            'failed_checks': [k for k, value in checks.items() if not value],
            'p99_ms': ordered[989] if ordered else None,
            'max_ms': ordered[-1] if ordered else None,
            'crossings_per_second': len(crossings) / elapsed if elapsed_valid else None}


def audit_worker_probe(source: str) -> dict:
    """Bounded structural check for the added probe, not native engine lock proof."""
    import re
    names = ('_on_physics_frame', '_m4_tick', '_m4_start_worker_probe', '_m4_poll_workers', '_m4_inject_sector_fault')
    forbidden = ('wait_for_task_completion', 'wait_for_group_task_completion', 'wait_to_finish',
                 'Mutex', 'Semaphore', '.lock(', '.wait(', 'OS.execute', 'OS.delay_',
                 'FileAccess', 'DirAccess', '.query(', '.transaction(')
    failures = []
    for name in names:
        match = re.search(r'^func ' + re.escape(name) + r'\([^\n]*\)[^\n]*:\n(?P<body>.*?)(?=^func |\Z)', source, re.M | re.S)
        if not match:
            failures.append(name + ':missing')
            continue
        for token in forbidden:
            if token in match['body']:
                failures.append(name + ':' + token)
    return {'passed': not failures, 'functions': names, 'failures': failures,
            'scope': 'Added measured application callbacks only; existing Canon reads and native engine synchronization are separate.'}


def summarize_stage_timings(observation: dict) -> dict:
    """Diagnostic inclusive spans; never add nested callbacks or infer native time."""
    names = ('server_physics_callback', 'player_position_callback',
             'boundary_reentry_callback', 'frontier_stay_callback', 'journey_checkpoint', 'telemetry_emit')
    samples = observation.get('samples', [])
    valid = bool(samples)
    totals = {name: {'calls': 0, 'total_usec': 0, 'max_iteration_usec': 0} for name in names}
    for sample in samples:
        stages = sample.get('stage_timings', {})
        for name in names:
            span = stages.get(name, {})
            calls, duration = span.get('calls'), span.get('duration_usec')
            if (not isinstance(calls, int) or calls < 0 or
                    not isinstance(duration, int) or duration < 0 or
                    (calls == 0 and duration != 0)):
                valid = False
                continue
            totals[name]['calls'] += calls
            totals[name]['total_usec'] += duration
            totals[name]['max_iteration_usec'] = max(totals[name]['max_iteration_usec'], duration)
    peak = max(samples, key=lambda sample: sample.get('duration_ms', -1)) if valid else None
    return {'qualified': valid, 'stages': totals, 'peak_sample': peak,
            'scope': 'Inclusive callback wall spans grouped by profiler iteration. Telemetry may nest inside frontier/position; journey may nest inside physics/position; boundary and frontier-stay may nest inside position. Do not sum spans or subtract unrelated process callbacks from native physics. Coalesced iterations cannot supply individual tick durations.'}


def summarize_checkpoint_timings(record: dict) -> dict:
    """Explicit experiment qualification; residual is inclusive, never hash time."""
    required = ('server_canon', 'server_journey', 'coordinator', 'registry',
                'canon_store_original', 'journey_store_original')
    bindings = record.get('bindings', {})
    valid = all(bindings.get(name) is True for name in required)
    samples = record.get('samples', [])
    valid = valid and isinstance(samples, list) and bool(samples)
    qualified_samples = []
    total_calls = 0
    for sample in samples if isinstance(samples, list) else []:
        if not isinstance(sample, dict):
            valid = False
            continue
        calls, duration = sample.get('checkpoint_calls'), sample.get('duration_usec')
        if type(calls) is not int or calls < 0 or type(duration) is not int or duration < 0:
            valid = False
            continue
        total_calls += calls
        child_total = 0
        for name in ('canon_read', 'journey_save'):
            span = sample.get(name, {})
            if not isinstance(span, dict):
                valid = False
                continue
            count, child = span.get('calls'), span.get('duration_usec')
            if type(count) is not int or count != calls or type(child) is not int or child < 0 or (count == 0 and child != 0):
                valid = False
                continue
            child_total += child
        if child_total > duration or (calls == 0 and duration != 0):
            valid = False
            continue
        qualified_samples.append(sample | {'inclusive_residual_usec': duration - child_total})
    return {'qualified': valid and total_calls > 0, 'checkpoint_calls': total_calls,
            'samples': qualified_samples,
            'scope': 'Original-handle delegated public child calls during checkpoint scope only. Residual includes serialization/hash, registry/bookkeeping and scheduling; it is not independently measured hash time. Native per-tick timing qualification remains separate.'}
