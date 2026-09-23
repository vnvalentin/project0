# Project0 — Shared Agent Repository Notes

Portable, git-tracked copy of the repo-scoped agent working notes so every agent
instance and every machine shares the same operating context. Agent
"repository memory" (`/memories/repo/`) is stored per-machine in VS Code
workspace storage and does **not** travel with the git remote — this file is the
version that does. Consult it at the start of a session and seed your repository
memory from it; keep it in sync when a convention changes.

Canonical, authoritative rules live in the documents linked below. This file is a
quick-reference and seed, not a replacement for them.

## Canonical rule sources (read these first)

- Delivery + safety: [AGENTS.md](../AGENTS.md), [docs/SYSTEMS-SPECIFICATION.md](../docs/SYSTEMS-SPECIFICATION.md),
  [docs/ENGINEERING-CONSTITUTION.md](../docs/ENGINEERING-CONSTITUTION.md),
  [docs/DEVELOPMENT-WORKFLOW.md](../docs/DEVELOPMENT-WORKFLOW.md).
- Delivery records: [docs/PROJECT-TRACKER.md](../docs/PROJECT-TRACKER.md),
  [docs/FEATURE-LIST.md](../docs/FEATURE-LIST.md),
  [docs/TECHNICAL-DEBT-TRACKER.md](../docs/TECHNICAL-DEBT-TRACKER.md).

## Branching + PR rule (mandatory; canonical in AGENTS.md + DEVELOPMENT-WORKFLOW.md)

- Every work item must be tied to a GitHub Issue before work starts. Link the
  issue from the branch/PR, slice record, tracker entries, and any local
  `.scratch` planning ticket references. Use `Fixes #N`/`Closes #N`/`Resolves #N`
  when the PR completes it; use `Refs #N` for related or partial work.
- `main` is always releasable; **never** commit directly to `main`.
- Every change gets its own branch cut from the latest `origin/main`, named
  `type/short-topic` (`slice/NNN-topic`, `fix/topic`, `docs/topic`,
  `chore/topic`). One logical change per branch.
- After every complete logical action, commit the resulting work, push the
  branch, update or create the pull request, and merge it when the delivery
  gate is green. Do not accumulate multiple completed actions in one uncommitted
  worktree.
- Land on `main` **only** via a `--no-ff` merged pull request (merge commit; no
  squash, no rebase).
- Merge gate (green before merge): full GUT suite
  (`scripts/run_gut_validation.sh` exit 0) + `scripts/check_record_sync.sh`
  exit 0 + records synchronized + review.
- The agent completing the change **merges when green** and deletes the branch.
  Tooling: `gh` (authenticated). `gh pr create --base main ...`;
  `gh pr merge <n> --merge --delete-branch`.

## Implementation ownership (canonical in AGENTS.md)

- Default: Claude CLI owns application-code, test-code, and
  implementation-facing delivery-record edits; Copilot orchestrates, hands off,
  validates, and reviews.
- **Standing authorization (user, 2026-09-18):** when Claude CLI is
  unavailable, interactive-only, rate-limited, or times out, Copilot implements
  directly rather than stopping. The delivery gate is unchanged — records-first,
  issue traceability, public-seam tests, validation evidence, record sync,
  branch/PR/merge. Note the fallback trigger in the slice record.
- Windows gotcha: `claude` and `claude -p` both open a full-screen TUI here, so
  VS Code reports "the command opened the alternate buffer" and returns no
  output; the `Claude:` VS Code tasks also fail on an unresolved
  `${relativeFile}`. A launched session wedges the persistent shell — recover by
  opening a NEW terminal, not by retrying the wedged one.

## Validation / build quick-reference

- Full suite: `scripts/run_gut_validation.sh` — writes `build/validation/gut.xml`
  and `build/validation/validation-summary.json` (expect `scripts_expected ==
  scripts_ran`, `exit_code: 0`).
- Record sync: `scripts/check_record_sync.sh` — needs 0 errors, exit 0 (a small
  set of pre-existing WARNs about slice docs with no named feature is expected).
- Focused GUT: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`
  (or `-gdir=res://tests/integration`).
- Per-script parse check: `godot --headless --check-only -s <script.gd>`.

## Headless server boot (gotchas)

- Correct invocation: `godot --headless --path . -s server/server_main.gd --quit-after N`.
  You **must** use `-s` (it is a `SceneTree` script); omitting `-s` runs nothing.
- `PROJECT0_ACCOUNTS_DB_PATH` must be a **bare `user://`-relative filename**
  (e.g. `boot.db`). An absolute `/tmp/...` path resolves under
  `user:///tmp/...`, which does not exist, and the server fail-closes on the
  accounts DB open.
- Opt-in LLM town at boot: `PROJECT0_LLM_TOWN_AT_BOOT=1` (default off). On the
  current hardware both `llama3:latest` and `qwen3:1.7b` are too slow to
  generate a valid town within a practical timeout, so the boot falls back to
  the validated fixture by design (the fallback guarantees a usable town).

## Slice / feature numbering

- Reserve the number in [docs/slices/SLICE-REGISTRY.md](../docs/slices/SLICE-REGISTRY.md)
  **before** creating `docs/slices/NNN-*.md`.
- The registry's own "Next free slice" line is the single source of truth; this
  file does not duplicate it (a stale copy here caused a near-collision).
