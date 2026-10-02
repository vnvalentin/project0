# Deterministic GDExtension validation bootstrap — #1396

Governing issue: https://github.com/vnvalentin/project0/issues/1396. This is committed M3 supporting debt for the Linux validation boundary, not a new content-system slice group.

## Outcome and boundary

The standard Linux GUT command must establish the tracked SQLite GDExtension registry before its first Godot process and retain a preparation result that rejects script, parse, or compile errors. The public seam is `scripts/run_gut_validation.sh`, which Project0 already defines as the standard repeatable server validation command.

The implementation is limited to the runner and its existing substituted-engine command control. It may create ignored, source-derived `.godot/extension_list.cfg` state in the validation checkout. It must not commit cache state, install a dependency, alter application behavior, change the vendored extension, replace the SQLite runtime, or claim M3 transaction/recovery acceptance.

The hypothesis is that the first process compiles typed server scripts before Godot discovers the vendored GDExtension. The cheapest discriminating check is the existing source-identity command control with a substituted engine that observes the registry before every engine invocation.

## Validation path

1. Linux-tooling preflight validates the focused command plan.
2. The source-identity control runs through the public GUT command with a substituted engine. It proves the registry is present before first launch and that a preparation script error fails closed with retained local evidence.
3. A bounded Linux native fixture verifies the cold-start behavior only after the focused control is green. Full GUT and record sync remain final delivery gates and are not represented by a focused pass.

Detailed runtime evidence and root-cause learning remain local under the user's disclosure instruction. Public records carry scope, status, dependencies, and next actions only.

Preparation reporting uses the owning Linux runtime's existing Python interpreter to encode JSON paths safely. No package installation is authorized or required; a missing reporter remains an execution blocker.

## Reusable preparation and isolated source

The public standard GUT command will consume a reusable Linux preparation entry point, `scripts/prepare_godot_project.py`. Its planned CLI accepts `--source-root`, a new `--prepared-root`, `--godot`, `--source-revision`, `--timeout-seconds`, and `--report`. It copies regular source into an exclusively created writable root, excluding private, generated, and credential-bearing state before content capture. It never rewrites the original checkout or read-only hosted source mount.

The helper seeds the fixed vendored SQLite registry before any Godot process. It temporarily disables the GUT editor plugin and file logging in the owned copy for asset preparation, restores the original plugin configuration for ordinary import, then restores exact original project bytes. Each phase rejects script/load/parse/compile errors, nonzero exits, unavailable output, or failed configuration custody. Non-script engine observations remain reported; no zero-engine-error claim follows from the script gate. Unknown configuration edits are preserved and fail qualification.

The caller owns the validation lock, source/artifact identity, complete consumer process lifecycle, evidence directory, and prepared-root teardown. The helper does not launch GUT, a game scene, a server, database actions, or a benchmark. The existing hosted source/read-only/no-network boundaries remain intact.

BDD: the standard runner imports in a fresh owned copy with the plugin disabled, qualifies with the plugin restored, runs GUT only after preparation succeeds, and removes its copy while leaving original source unchanged. Any preparation script failure prevents GUT. Unknown registry/configuration or unavailable evidence cannot leave a stale passing summary. Source identity propagates unchanged through Git checkout and explicitly identified gitless artifact inputs.

The existing `scripts/test_gut_source_identity.py` remains the agreed command seam and substituted-engine control. Its next tracer observes staged project configuration and cleanup through actual command calls. Native qualification and full GUT remain separate required gates. Rollback removes only the helper/runner changes; no application schema, dependencies, privileges, runtime deployment or Windows client behavior changes.
