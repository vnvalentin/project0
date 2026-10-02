"""M4 acceptance evaluator. It consumes observations, never supplies missing ones."""
import math


def evaluate(observation: dict, cleanup: bool) -> dict:
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
    checks = {
        'complete_tick_samples': complete,
        'finite_durations': finite,
        '30hz': observation.get('configured_tick_rate') == 30,
        'full_workload_each_tick': complete and all(s.get('peers') == 10 and s.get('ready') == 10 and s.get('sectors', 0) >= 4 and s.get('npcs', 0) >= 10 and s.get('bodies', 0) >= 15 and s.get('triggers', 0) >= 15 for s in samples),
        'p99_at_most_33_3ms': bool(ordered) and ordered[989] <= 33.3,
        'max_at_most_50ms': bool(ordered) and ordered[-1] <= 50,
        'crossings_at_least_two_per_second': elapsed_valid and len(crossings) / elapsed >= 2,
        'canon_timing_observed': bool(observation.get('canon_reads')),
        'isolation_observed': all(isolation.get(k) is True for k in ('healthy_canon_unchanged', 'sector_fault_contained', 'background_contention_observed', 'structural_nonblocking_verified', 'lock_wait_observed')),
        'runtime_errors_absent': observation.get('errors') == [],
        'cleanup_verified': cleanup is True,
    }
    return {'passed': all(checks.values()), 'checks': checks,
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
