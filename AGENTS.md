# Project0 Agent Guidance

All development follows [the Engineering Constitution](docs/ENGINEERING-CONSTITUTION.md).
It is operating logic for implementation, not background documentation.
Use [TPSA](docs/tpsa.md) as the core behavior profile for all activities.

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
  requirement (see Code Style in `CLAUDE.md`), not a standalone tool.
- Lint: Not applicable. No GDScript linter is installed.
- Build: Not applicable during this phase. No export presets or packaged builds
  exist yet; the project runs from source via the Godot 4.3 editor/headless
  binary.
- Runtime or integration validation: `godot --headless --path . <scene.tscn>`
  for a bounded number of frames (e.g. with `--quit-after`), or manual editor
  run for anything requiring visual/input confirmation. Server-container and
  Ollama/SQLite validation are out of scope until those systems are built.

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
- Implementation ownership: Copilot performs orchestration, bounded handoffs,
  validation coordination, and review. Claude CLI owns application-code,
  test-code, and implementation-facing delivery-record edits unless the user
  explicitly authorizes Copilot to edit directly. If Claude CLI is unavailable
  or times out, stop and report the blocker; do not silently implement the
  change with Copilot tools.
- Before editing, state the user outcome, scope, non-goals, affected boundary,
  unacceptable outcomes, hypothesis, and cheapest discriminating check.
- Test at the public seam and run the narrowest relevant validation first.
- Stop on unexpected failure, degraded health, missing evidence, or unclear
  security boundaries.
- Never claim runtime behavior without runtime evidence.
- Do not add dependencies, migrations, permissions, or external side effects
  without documenting their safety and rollback implications.
- Before starting or changing delivery work, read the repository's Copilot
  instructions and use the Project Tracker, Feature List, and Technical Debt
  Tracker according to their stated ownership.
- Before the first edit, confirm the foundation gate is closed and record the
  primary phase, feature or liability, and implementation slice in the three
  delivery records.