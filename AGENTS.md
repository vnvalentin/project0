# Project0 Agent Guidance

All development follows [the Engineering Constitution](docs/ENGINEERING-CONSTITUTION.md).
It is operating logic for implementation, not background documentation.
Use [TPSA](docs/tpsa.md) as the core behavior profile for all activities.

The tool-neutral systems/implementation contract is
[docs/SYSTEMS-SPECIFICATION.md](docs/SYSTEMS-SPECIFICATION.md) (formerly
`CLAUDE.md`, now a pointer stub). Any LLM working this repo — Copilot, Claude, or
another — treats it as authoritative.

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
- Build: Not applicable during this phase. No export presets or packaged builds
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

  Ollama/SQLite validation are out of scope until those systems are built.

## Server and Linux execution boundary

The Project0 game server runs in a container on the Linux machine at
`192.168.1.254`. The Windows client may run on this machine or on another
Windows machine, but that does not change the server boundary.

Any server-side, container, or Linux-only command MUST execute on
`192.168.1.254` through SSH. Do not substitute a local Windows or WSL command
for server work. If SSH access to `192.168.1.254` is unavailable, stop and
report the blocker rather than running the command locally.

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
- Branch per change and merge via pull request: `main` is always releasable and
  is never committed to directly. Cut a `type/short-topic` branch (`slice/`,
  `fix/`, `docs/`, `chore/`) from the latest `origin/main` for every change, and
  land it on `main` only through a `--no-ff` merged pull request once the
  validation gate is green (full GUT suite + `check_record_sync.sh` exit 0). The
  After every complete logical action, commit the resulting work, push the
  branch, update or create the pull request, and merge it when the validation
  gate is green; do not accumulate multiple completed actions in one uncommitted
  worktree. The agent completing the change merges when green and deletes the
  branch. See
  [docs/DEVELOPMENT-WORKFLOW.md](docs/DEVELOPMENT-WORKFLOW.md) "Branching and
  pull requests".
- Shared agent context: at the start of a session, consult
  [.agents/repo-memory.md](.agents/repo-memory.md) — a git-tracked, portable copy
  of the repo-scoped agent working notes (agent `/memories/repo/` is per-machine
  and does not sync via the remote). Seed your repository memory from it, and
  keep it in sync when a convention changes.
- Implementation ownership: Copilot performs orchestration, bounded handoffs,
  validation coordination, and review. Claude CLI owns application-code,
  test-code, and implementation-facing delivery-record edits unless the user
  explicitly authorizes Copilot to edit directly. **Standing authorization
  (user, 2026-09-18): if Claude CLI is unavailable, interactive-only,
  rate-limited, or times out, Copilot is authorized to implement directly
  rather than stopping.** The fallback changes who edits, never what the
  delivery gate requires: records-first, GitHub issue traceability,
  public-seam tests, real validation evidence, and record sync still apply in
  full. Note the fallback trigger in the slice record so the ownership
  deviation stays auditable.
- Delivery gate: Claude must create or update the governing GitHub issue,
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
- Test at the public seam and run the narrowest relevant validation first.
- Stop on unexpected failure, degraded health, missing evidence, or unclear
  security boundaries.
- Root-cause learning gate: every unexpected runtime failure, user-reported
  defect, validation failure, or integration surprise must be recorded in the
  affected slice's `Root-cause learning` section before completion. Record the
  symptom, public seam, falsifiable hypothesis, discriminating check,
  confirmed root cause, why existing tests missed it, countermeasure,
  regression evidence, and any remaining limitation or debt link. A chat or
  terminal log alone is not durable evidence.
- Never claim runtime behavior without runtime evidence.
- Do not add dependencies, migrations, permissions, or external side effects
  without documenting their safety and rollback implications.
- Before starting or changing delivery work, read the repository's Copilot
  instructions and use the governing GitHub issue, Project fields, labels,
  milestones, and linked evidence as the active delivery record.
- Before the first edit, confirm the foundation gate is closed and record the
  primary outcome, phase, parent issue, milestone commitment, and
  implementation slice in GitHub.
- Allocate slice and feature numbers only via
  [docs/slices/SLICE-REGISTRY.md](docs/slices/SLICE-REGISTRY.md): reserve the
  next free number there before creating a slice. A single integrator owns
  number allocation and the delivery trackers; any parallel autonomous worker
  MUST use its reserved block (100–199) and disjoint files so concurrent work
  never collides on a slice/feature number.

## Features and Slices are tracked as GitHub issues (2026-09-20)

`docs/FEATURE-LIST.md` and `docs/slices/*.md` (including `SLICE-REGISTRY.md`)
are a **frozen historical archive** of everything delivered before this date —
do not add new entries to them. A new **Feature** is a GitHub issue labeled
`Feature`, with `Parent goal: #N` in its body when it advances a Goal issue. A
new **Slice** is a GitHub issue labeled `Slice`, with `Parent feature: #N` in
its body when it advances a Feature issue. This removes the file-based
number-allocation race for those two record types; GitHub issue numbers are
assigned by GitHub itself. `docs/PROJECT-TRACKER.md`,
`docs/TECHNICAL-DEBT-TRACKER.md`, `docs/FEATURE-LIST.md`, and `docs/slices/`
are frozen historical or explanatory archives. GitHub Issues and Project #2
are the active records, per [docs/RECORD-OWNERSHIP.md](docs/RECORD-OWNERSHIP.md).

A Feature issue states the gap between the current condition and its parent
Goal's ideal condition, resolved only by measurable proof the gap closed; a
Slice issue names the root cause one step resolves toward that proof. See
[Vision, Goal, Feature, and Slice semantics](docs/DEVELOPMENT-WORKFLOW.md#vision-goal-feature-and-slice-semantics-2026-09-20)
for the full definitions before opening either.