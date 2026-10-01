# Project0 Agent Guidance

All development follows [the Engineering Constitution](docs/ENGINEERING-CONSTITUTION.md).
It is operating logic for implementation, not background documentation.
Use [TPSA](docs/tpsa.md) as the core behavior profile for all activities.

The tool-neutral systems/implementation contract is
[docs/SYSTEMS-SPECIFICATION.md](docs/SYSTEMS-SPECIFICATION.md) (formerly
`CLAUDE.md`, now a pointer stub). Every agent working in this repository treats
it as authoritative.

## Repository commands

- Test: `scripts/run_gut_validation.sh` runs the automated GUT suite under
  `tests/unit/` and `tests/integration/`
  ([DT-002](docs/TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework)
  remediated: framework installed at `addons/gut/`; migration of the
  remaining hand-rolled `scripts/test_*.gd` smoke tests is tracked
  incrementally). `godot --headless --check-only -s <script.gd>` remains
  available for per-script parse/error checks on non-GUT scripts.
- Delivery validation: `scripts/run_gut_validation.sh` is the standard
  repeatable unit-validation command. It must pass before a slice is marked
  complete and emits `build/validation/gut.xml` plus
  `build/validation/validation-summary.json` as machine-readable telemetry.
  Slice-specific integration or runtime checks must emit an equivalent
  command result and be recorded in the slice validation section.
- Typecheck: Not applicable as a separate step. GDScript 2.0 static types are
  enforced by the same `--check-only` parse above; strict typing is a code-style
  requirement (see Code Style in
  [docs/SYSTEMS-SPECIFICATION.md](docs/SYSTEMS-SPECIFICATION.md)), not a
  standalone tool.
- Lint: Not applicable. No GDScript linter is installed.
- Build: Not applicable. No export presets or packaged builds
  exist yet; the project runs from source via the Godot 4.3 editor/headless
  binary.
- Runtime or integration validation: `godot --headless --path . <scene.tscn>`
  for a bounded number of frames (e.g. with `--quit-after`), or manual editor
  run for anything requiring visual/input confirmation. Server-container and

## Windows-required work

Any issue or pull request that changes the Windows client, Windows launcher,
Windows-native code, Windows packaging, or Windows-only tests must carry the
`platform:windows-required` GitHub label. Treat that label as a hard execution
boundary:

- The implementation checkout must be created, pulled, and modified on the
  Windows development machine assigned to the work.
- Linux machines may inspect the issue, review a remote diff, and coordinate the
  handoff, but must not pull the Windows-required branch, run its client or
  Windows tests, build its Windows artifacts, or claim Windows validation.
- The Windows machine must run the focused Windows tests and the applicable
  repository validation, recording the command, host, result, and artifact in
  the governing issue and pull request before merge.
- A Windows-required change is not merge-ready when its issue lacks the label,
  its branch was implemented on Linux, or its Windows evidence is missing.

Apply the label when any changed path is under `native/windows_launcher/`, has a
Windows-only build constraint, changes Windows packaging or installer behavior,
or changes a client path whose acceptance depends on Windows runtime behavior.

Before opening or updating a pull request for Windows-required work, verify that
`platform:windows-required` is present on both the governing GitHub issue and the
pull request. Add it to the pull request explicitly with
`gh pr edit <number> --add-label platform:windows-required`; an issue label alone
does not satisfy CI source approval.

  Ollama/SQLite validation are out of scope until those systems are built.

## Server and Linux execution boundary

The Project0 game server runs in a container on the Linux machine at
`192.168.1.254`. The Windows client may run on this machine or on another
Windows machine, but that does not change the server boundary.

Any server-side, container, or Linux-only command MUST execute on
`192.168.1.254` through SSH. Do not substitute a local Windows or WSL command
for server work. If SSH access to `192.168.1.254` is unavailable, stop and
report the blocker rather than running the command locally.

### Windows shell and SSH quoting

On Windows, agent terminals run PowerShell 7 (`pwsh`). Do not hand-build
`ssh host "..."` command strings: each layer (PowerShell, ssh, the remote shell)
re-parses quotes, which strips Docker/Go template braces, `$` variables and
embedded quotes. Send the remote work through stdin with the helper instead:

```powershell
scripts/remote.ps1 'cd /data/code/project0 && docker inspect --format "{{.Name}}" project0-game-server'
Get-Content job.sh -Raw | scripts/remote.ps1
```

Write the script exactly as in a bash terminal and wrap it in single quotes; the
remote exit code becomes `$LASTEXITCODE`. It uses `BatchMode`, so missing key
access fails fast (exit 255) instead of waiting at a password prompt. From Git
Bash, use a quoted heredoc: `ssh -T vic@192.168.1.254 bash -s <<'EOF'`.
`bash` in PowerShell must resolve to Git Bash, not `C:\Windows\System32\bash.exe`
(the WSL launcher); WSL is not a supported shell for this repository.

## Project boundaries

- Primary product boundary: This repository owns the Godot 4 client and
  headless server code, local player identity/session handling for
  single-machine development, and (once built) the JIT world generation and
  canon persistence logic. It does not own or reimplement Godot engine
  internals, the Ollama runtime itself, or any third-party auth provider.
- External systems: Local Ollama API (`http://127.0.0.1:11434`, server-side
  only, via `shared/local_llm_client.gd`) for future JIT generation; none are
  exercised by the current identity-gate/movement slice.
- Sensitive data rules: No passwords, tokens, or payment data exist in this
  slice. The local identity gate stores only a player-chosen display name
  in-memory (not persisted to disk or a database) until a real auth/session
  design is specified.
- Retention and deletion rules: Nothing in this slice is persisted; there is
  no save file or database yet, so there is nothing to retain or delete. Any
  future SQLite canon store must define its own retention/deletion rules
  before it is introduced.
- Deployment and rollback unit: A single Godot project checkout run directly
  from source (editor or `godot --headless`). There is no packaged
  build/deploy artifact yet; rollback is reverting the working tree to a
  prior commit once version control is initialized.

## Foundation gate

Before implementation, inspect `docs/PROJECT-SETUP-CHECKLIST.md`. If
`.foundation-incomplete` exists or any active delivery record still contains an
unfilled double-curly-brace placeholder token, the repository is in foundation
setup, not implementation. Complete and validate `AGENTS.md`, `CONTEXT.md`,
`docs/PROJECT-TRACKER.md`, `docs/FEATURE-LIST.md`, and
`docs/TECHNICAL-DEBT-TRACKER.md` together, then remove `.foundation-incomplete`.
Do not create implementation slices or product code while this gate is open.

## Agent requirements

- Preserve unrelated user changes.
- Before planning or running validation, or recommending a missing dependency,
  follow [validation ownership](docs/validation-ownership.md) and pass its plan
  preflight. Match the dependency to its owning runtime first: SQLite and Canon
  persistence execute on the Linux server; Windows validates client behavior.
- Experiment lifecycle rule: every experiment harness owns setup, execution,
  evidence capture, and teardown in one non-interactive path. It must create
  isolated temporary state, enforce clean-target preconditions, emit
  machine-readable evidence on success or failure, and remove temporary state
  in a `finally`/cleanup path. Missing external targets or artifacts must fail
  closed with a recorded blocker; never wait for user prompts during setup,
  execution, or teardown.
- Branch per slice and merge via pull request: `main` is always releasable and
  is never committed to directly. Every slice gets its own
  `slice/<issue-number>-<short-topic>` branch cut from the latest `origin/main`
  and its own pull request. Fixes, docs, chores, and experiments likewise get
  their own `type/short-topic` branch. After every completed logical edit, run
  the narrowest relevant validation and commit the resulting work before
  starting the next edit; do not accumulate completed edits in an uncommitted
  worktree. Push the branch after each commit that is ready to share, update or
  create the pull request, and land it on `main` only through a `--no-ff` merged
  pull request once the validation gate is green (full GUT suite +
  `check_record_sync.sh` exit 0). The agent completing the change merges when
  green and deletes the branch. See
  [docs/DEVELOPMENT-WORKFLOW.md](docs/DEVELOPMENT-WORKFLOW.md) "Branching and
  pull requests".
- Shared agent context: at the start of a session, consult
  [.agents/repo-memory.md](.agents/repo-memory.md) — a git-tracked, portable copy
  of the repo-scoped agent working notes (agent `/memories/repo/` is per-machine
  and does not sync via the remote). Seed your repository memory from it, and
  keep it in sync when a convention changes.
- GitHub operations: use the authenticated `gh` CLI for every GitHub read and
  mutation. Prefer a typed `gh` command. When the core CLI has no command for a
  required GitHub resource, use the authenticated `gh api` subcommand through a
  reviewed repository helper; do not use raw HTTP clients, direct API tooling
  outside `gh`, browser scraping, or alternate GitHub integration tools. The
  milestone lifecycle helper is `scripts/gh_milestone.sh`.
- Implementation ownership: Copilot implements application code, tests, and
  implementation-facing delivery records directly, and owns validation and
  review. No external CLI handoff or fallback authorization is required.
  Records-first, GitHub issue traceability, public-seam tests, real validation
  evidence, and record sync still apply in full.
- Delivery gate: the implementing agent must create or update the governing GitHub issue,
  planning ticket, and required issue links before implementation begins. Code
  and tests passing is insufficient to mark a slice complete unless the
  SDD/BDD/TDD, validation evidence, review status, and GitHub links are
  present and verified. Session limits, timeouts, and validation failures leave
  the slice blocked or awaiting evidence. GitHub Issues and Project #2 are the
  only active delivery records; `PROJECT-TRACKER.md` is historical context and
  is never updated for new work.
- Before editing, state the user outcome, scope, non-goals, affected boundary,
  unacceptable outcomes, hypothesis, and cheapest discriminating check.
- Before starting work, identify the governing GitHub Issue; create one when no
  suitable issue exists. Link it from the branch/PR, slice record, tracker
  records, and any local `.scratch` planning ticket references. Local planning
  tickets do not replace the GitHub Issue.
- For every task, follow [goal-first execution and discovery handling](docs/DEVELOPMENT-WORKFLOW.md#goal-first-execution-and-discovery-handling):
  name the issue's goal, acceptance criteria and non-goals; capture discoveries
  first; resolve goal blockers through Jidoka; record non-blockers and return
  immediately to the original goal. Factual capture is pre-authorized, not
  permission to expand scope.
- Test at the public seam and run the narrowest relevant validation first.
- Stop affected work for goal-blocking failures, failed mandatory gates, or
  unclear safety/security boundaries; classify other discoveries using the
  goal-first rule.
- Completion persistence rule: do not stop an implementation, experiment, or
  delivery path while its governing GitHub issue remains open. Continue until
  the issue is closed with acceptance evidence, or explicitly mark it blocked
  or failed with the symptom, public seam, evidence, confirmed root cause (or
  the unresolved hypotheses), acceptance criteria, rollback boundary, and next
  owner/action recorded in the issue. A green local test, a merged code change,
  or a partial artifact is never sufficient to report completion while the
  governing issue remains open.
- Root-cause learning gate: every unexpected runtime failure, user-reported
  defect, validation failure, or integration surprise must be recorded in the
  affected slice's `Root-cause learning` section before completion. Record the
  symptom, public seam, falsifiable hypothesis, discriminating check,
  confirmed root cause, why existing tests missed it, countermeasure,
  regression evidence, and any remaining limitation or debt link. A chat or
  terminal log alone is not durable evidence. For non-blocking discoveries,
  link the deferred issue and mark uninvestigated fields unknown; this gate
  does not require unrelated diagnosis before completing the current goal.
- Jidoka and blocker closure follow the canonical goal-first rule linked above:
  record the problem and Technical Debt, establish root cause, apply a focused
  fix, validate and close with evidence before resuming the affected goal.
  Missing authority or access leaves an explicit blocker and next owner/action,
  never a bypass or completion claim.
- Never claim runtime behavior without runtime evidence.
- Do not add dependencies, migrations, permissions, or external side effects
  without documenting their safety and rollback implications.
- Before starting or changing delivery work, read the repository's Copilot
  instructions and use the governing GitHub issue, Project fields, labels,
  milestones, and linked evidence as the active delivery record.
- Before the first edit, confirm the foundation gate is closed and record the
  outcome, applicable milestone and named slice group, governing issue and
  parent links in GitHub. Cross-cutting/uncommitted work records why a milestone
  does not apply. Follow the [delivery hierarchy](docs/DEVELOPMENT-WORKFLOW.md#milestones-slice-groups-and-linked-issues);
  phases are retired and existing Phase fields are legacy metadata.
- GitHub assigns new issue numbers. Preserve milestone IDs, slice-group
  identifiers and existing issue relationships; frozen archives do not allocate
  new work. Parallel workers use disjoint implementation scopes and explicit
  issue ownership, not reserved archive-number blocks.

## Milestone delivery and GitHub record ownership

`docs/FEATURE-LIST.md` and `docs/slices/*.md` (including `SLICE-REGISTRY.md`)
are a **frozen historical archive** of everything delivered before this date —
do not add new entries to them. Milestone descriptions own named slice groups
and their Included issues; GitHub issues own bounded work, evidence and resolution.
An issue labeled `Slice` is not automatically a milestone slice group. Preserve
applicable Feature/Goal and Slice/Feature parent links without inventing a second
required hierarchy. Technical Debt is a linked GitHub liability with impact,
owner and remediation evidence, assigned a milestone only when committed.
`docs/PROJECT-TRACKER.md`,
`docs/TECHNICAL-DEBT-TRACKER.md`, `docs/FEATURE-LIST.md`, and `docs/slices/`
are frozen historical or explanatory archives. GitHub Issues and Project #2
are the active records, per [docs/RECORD-OWNERSHIP.md](docs/RECORD-OWNERSHIP.md).

Before creating or completing work, read
[Milestones, slice groups, and linked issues](docs/DEVELOPMENT-WORKFLOW.md#milestones-slice-groups-and-linked-issues).
Issue closure does not prove slice or milestone acceptance; each outcome needs
its own evidence and resolved blocking work.
