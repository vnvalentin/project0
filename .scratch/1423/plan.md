# Pure network-default environment isolation — #1423

Governing issue: https://github.com/vnvalentin/project0/issues/1423. Milestone 3 / M3.2 supporting validation liability, related #1396 and #1341. Project #2 status and scope were verified by the coordinator before this plan. Foundation checklist is complete; no foundation marker or active foundation placeholder was found. Shared Harness guidance consumed in this continuation: main `77de008a0f28eb91726527d543adb435735a2157`. The branch starts from freshly verified accepted main `4033b5cc3263db14b323abb663d59d5d48013388`, with exact #1396 dependency `cf5803ae9410acb0ebce73df4a0c4ec8cfa5270b` merged, then its accepted-main integration `285c814a4919c726f5488f401ba99cd3613a0a56` merged to keep the future stack diff narrow. The concurrent owner fix from frozen #1396 `0e099fb951d5da360abc1d7293e6b2672adaebce` is preserved by an exact dependency merge; this branch adds only boolean snapshot assertions and focused selection alignment.

## Outcome, scope, and hypothesis

The user outcome is a trustworthy validation result while the surrounding validation environment remains confined to loopback. The owner's three pure cases in `tests/unit/test_lan_config.gd` remain: defaults with variables absent during getters, explicit empty overrides, and populated overrides with invalid-port fallbacks. Only their whole-snapshot assertions are changed to boolean equality, preserving fixed messages and getter expectations. Save presence and exact values of `PROJECT0_SERVER_BIND_ADDRESS`, `PROJECT0_SERVER_HOST`, and `PROJECT0_SERVER_PORT`; clear them; synchronously query the three defaults; restore presence and values before the original assertions. No await, socket, subprocess, application/default constant, Windows, Canon, deployment, or unrelated test changes occur in that interval. Environment values are never printed or added to evidence.

The falsifiable hypothesis is that inherited loopback host/port overrides affect the existing supposedly override-free getters. The cheapest RED selects only `test_defaults_to_localhost_with_no_override` in GUT under explicit loopback overrides. Application constants and expected assertion values stay unchanged. Focused GREEN selects exactly the existing default case under fixed inherited loopback overrides and checks exact outer restoration with a boolean assertion. The separate empty/populated pure cases and absence/empty input coverage remain mandatory full-suite gates. No same-prefix renames or duplicate fixtures are introduced.

## Frozen focused command and capture contract

`python3 .scratch/1423/run-focused.py --source-revision <exact-clean-HEAD> --run-id <new-id> --mode red`

GREEN uses the same command with `--mode green`. The wrapper owns the nonblocking shared lock `/tmp/project0-m4-01a0fcfa-validation.lock` throughout preparation, execution, receipt qualification, and teardown. A coordinator review and explicit native window are required before either invocation. Static preflight is `python3 scripts/check_validation_ownership.py --plan .scratch/1423/validation-plan.json --output build/validation/1423/plan-ownership.json`.

Reuse only the SHA-pinned private #1396 lifecycle module (`448d77e2793693fdbd2cf74477aa5e1c2d3203473bedb0d0fb54fcdacee4c03c`), binding its ROOT explicitly to this checkout. Absence or hash drift blocks execution. This uses reviewed default-SIGCHLD, WNOWAIT/pidfd child identities, subreaper cleanup, fresh HOME/XDG, core-dump exclusion and whole-lifecycle containment. It is a local prerequisite, not a portable CI dependency.

The #1396 helper is pinned to SHA-256 `13434bab2d8e45138268b691723df3fbd8314f2d9c944dd657df7173c44ab6b9` from `cf5803`; execute an owned snapshot only. Helper exclusions preexclude private/cache/log/live-database/credential paths before source copying. Require clean exact Git HEAD at start/end; pin every selected source byte and mode, original configuration and helper digest. Verify actual preparation source/root/manifest, both canonical phase records/logs, exact restored configuration, regular registry and absent override before the consumer. Engine identity must be exactly `4.3.stable.official.77dcf97d8`, queried in an owned empty directory.

GUT receives an explicit minimal environment with only fixed synthetic loopback overrides, disabled login modes, and owned empty HOME/XDG state. Its command is `godot --headless --path <owned-project> -s addons/gut/gut_cmdln.gd -gconfig= -gtest=res://tests/unit/test_lan_config.gd -gunit_test_name=test_defaults_to_localhost_with_no_override -gdisable_colors -gexit -gjunit_xml_file=<owned-xml>`. The source selection and exact XML testcase names are qualified; surrounding socket/server/subprocess cases are excluded from this focused selection and remain mandatory in later full validation. No application scene is launched. Static audit of startup autoloads confirms internal signal registration and an idle telemetry queue, without starting transport/authentication.

Automatic engine file logging is disabled with the fixed owned override before GUT and remains disabled during helper imports. Pipe bytes are transient and bounded; retain only script-error/non-script-error/output-validity/exit/timeout booleans. Unknown text is discarded. The selected test's JUnit contains only source-authored assertion results and fixed synthetic override inputs; parse it in owned temporary state and retain a reduced XML containing known testcase names and numeric failure/error/skip counts, with no assertion messages or system output. Retain preparation canonical logs, receipt and reduced result outside the temporary root. No credentials, raw GUT logs, environment values, live databases or authenticated observations are captured.

## Lifecycle, gates, and rollback

The wrapper reserves a new private result directory, clean source qualification and a new owned temporary root. Preparation imports are each limited to 40 seconds, helper observation to 100 seconds and pure GUT to 30 seconds; the nominal stage budget is 150 seconds with reserved teardown. Bounded final source/Git checks may add time; this is not an enforced outer deadline. Direct child identities remain unreaped until unified pidfd/subreaper cleanup; no numeric process-group termination is introduced. Missing/invalid XML, wrong selection, script error, timeout, unavailable engine/helper, failed preparation, source change or unknown configuration/registry/override custody fails closed. RED requires exact GUT assertion-failure exit 1 and the existing one-case failure with no error/skip; GREEN requires exit 0 and exactly the existing default case passing. A negative crash exit cannot qualify RED even with complete failure XML. Neither is full regression or M3 acceptance.

Before deletion, recheck source, every selected byte/mode, helper digest, original configuration, registry and the exact fixed override; preserve the owned stage on unknown custody. Cleanup failure fails the result. Restore/remove only the known override, never replace unknown edits. Reserve the new private result before qualifying the lifecycle, helper or lock; missing/drifted prerequisites retain fixed structured blockers without launching an engine. Final result records source/command identity, stage verdicts, selected-case counts, retention and cleanup; exclusive write and exact readback precede any retention claim. Source-only syntax, ownership preflight and record sync qualify this plan; independent review and the coordinator's window precede native validation. Full GUT plus record sync and final Standards + Spec review remain delivery gates.

Rollback reverts only the test and owned validation records; no application/default, schema, host setting or production state changes. Intended PR base is `chore/1396-gdextension-bootstrap`; the exact reviewed frozen dependency is now `8a870cebb64ca16eab49c40fce13ef205e184624`, integrated without editing its branch. The previously stale `cf5803` base would have included unrelated accepted Windows changes; the exact dependency-base integration resolves that scope problem before PR creation.

## Root-cause learning

The pure default test assumed an override-free environment while full validation deliberately supplied loopback overrides. The coordinator qualified the expected RED. The countermeasure isolates only synchronous getters, restores exact presence/value state before assertions, and preserves the owner's separate empty/populated cases. Focused GREEN and full delivery remain pending. Detailed learning and execution evidence remain private; public records contain status, countermeasures and next actions.

### Focused command safety

Prerequisite failures must retain a structured blocker before any engine launch. The countermeasure reserves the owned result before prerequisite qualification, verifies retention by readback, and requires the expected assertion-failure verdict for RED. Copied command controls pass. Next action: coordinator review of the frozen command before native validation.

### JUnit aggregate qualification

Selected case tags alone cannot qualify aggregate verdicts. The parser binds root/suite totals, validates error/skip declarations, and preserves GUT's assertion-failure semantics. Copied controls pass. The XML does not reveal the exact failed/passed assertion split within a failing testcase; retain that limitation and require the declared totals to be consistent.

### Concurrent-fix reconciliation

Concurrent owner fixes are preserved. Snapshot comparisons use boolean assertions with unchanged fixed messages to avoid rendering environment values on failure. The focused command selects the existing default case; other pure cases and full GUT remain mandatory full-validation coverage. Next action: coordinator review and controlled GREEN after prerequisites qualify.

### Reviewed dependency refresh

The reviewed validation dependency is integrated into this branch without editing its owner branch. Boolean snapshot assertions and focused selection are preserved. Relevant copied controls, ownership preflights and record sync pass. Native GREEN and full delivery remain pending.

### Setup frontier and disclosure correction

The attempted GREEN stopped at the lock prerequisite before consumer execution. This is a contained setup frontier and does not establish application failure. Detailed learning is retained privately; the tracked plan is limited to status, countermeasures and next actions. The coordinator must qualify the lock and configuration boundary before authorizing further native work.
