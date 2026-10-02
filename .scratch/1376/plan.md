# M4.1 baseline
Governing issue: https://github.com/vnvalentin/project0/issues/1376
Parent #204; Milestone 4 / M4.1. Brief: https://github.com/vnvalentin/project0/issues/1376#issuecomment-5954636188
Foundation closed at 75655f6b. Real admitted ENet peers and authoritative server tick, four neighboring Canon details, real NPC/collision/Area load. No live deployment or Windows acceptance.
Fail closed on missing samples, active counts, incomplete isolation observations, runtime errors or teardown. Record processing duration separately from 30Hz wall periods. No inferred worker or lock evidence.

### Smoke investigation checkpoint

The 60-observation container smoke at c02373a retained four coalesced physics-iteration errors and a 97.113 ms observed maximum. The confirmed measurement limitation is EngineProfiler aggregation, not yet the cause of CPU delay. Keep the 32-task probe unchanged for comparison. Next diagnostic observes only the owned container cgroup-v2 cpu.stat usage/period/throttling counters at 50 ms intervals; per-sample wall timestamps permit correlation. Sampling is outside the server process and never reads cgroup process arguments or environments. Full runtime acceptance remains blocked on exact consecutive tick observations. Governing record: https://github.com/vnvalentin/project0/issues/1376#issuecomment-5955327913.

Matched diagnostic comparison approved by the evaluation owner: same immutable source, 60 observations each, synthetic worker counts 32 versus 0. Both retain all real entity/peer/sector load, four async generator timeouts, sector fault, CPU/memory limits, source custody, clean-target preconditions, and teardown. `--diagnostic-workers` is rejected for the 1,000-tick baseline; the zero-worker diagnostic cannot pass worker-contention acceptance. Compare cpu.stat and native physics spans without attributing causality from the first smoke alone.

Matched comparison at 6d8adcf retained both full 60-observation reports (151246688429Z with 32 workers and 151332495781Z with 0). Both verified cleanup and source custody. The added external CPU observer reported a teardown race: Docker removed the exited server cgroup before its client process exited, even though the complete observation was already atomically saved. The runner now distinguishes that completed state, bounds the client-exit wait, and retains the final available CPU sample; missing cgroups before complete observation still fail. Original failure reports remain unchanged. This does not change worker load, timing values, or acceptance.
