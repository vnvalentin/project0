# M4.1 checkpoint attribution experiment
Governing issue: https://github.com/vnvalentin/project0/issues/1376
Parent #204; architecture consumer #205; Milestone4 / M4.1.
Records-first scope: https://github.com/vnvalentin/project0/issues/1376#issuecomment-5959095565
Foundation closed; accepted source424a71092d8f4b91fecdcf962aa19faa5a4c9510.
Shared Harness guidance consumed77de008a0f28eb91726527d543adb435735a2157.

Outcome: separate inclusive checkpoint Canon SELECT/decode and Journey binding/UPSERT spans before selecting a bounded remedy. Public seams are unchanged CanonRepository.get_canonical_sector and JourneyRepository.save delegated by experiment subclasses; report qualification and real isolated repository/registry assembly are the agreed controls. No production files, database reopening/schema changes, workload reductions, deployment, thread/writer migration or process split.

Hypotheses: Canon read/decode dominates; Journey save dominates; both remain small and inclusive residual covers hash/bookkeeping/scheduling; or observer binding is incomplete. Cheapest discriminating checks: public report rejects missing bindings/spans, real shared/dedicated stores preserve returned Canon and persisted Journey state, stale registry/missing Canon/different handle reject qualification. Child wrappers call unchanged super; original store identities and server/coordinator/registry assignments must be observed. Outside-checkpoint calls do not contribute. Inclusive residual is not an independent hash measurement.

Unacceptable: counting unbound observers as zero work, silently changing default baseline CLI/acceptance, relabeling old failed results, foreign cleanup, product optimization. Setup/execution/evidence/teardown are owned and noninteractive; all stores/private paths fresh, cleanup in after_each/finally and source identity in results. Native validation waits for coordinator window release. Focused controls first; one target supported-load1000 span10 measurement only after binding controls pass, without run-to-green repetitions. Final full GUT plus record sync and independent Standards/Spec required. Current M4.1 capacity acceptance remains failed/blocked at original746 evidence.

Root-cause learning: retained supported548.826ms single-step peak associates with journey534.269ms; finer internal cause unknown. Existing profiler coalescing limits exact P99. New observers must preserve these limitations. Source-only preparation is not native proof.
