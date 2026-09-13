# Record Ownership Rule (draft)

Status: **draft** for review. Fold into [AGENTS.md](AGENTS.md) and
[DEVELOPMENT-WORKFLOW.md](DEVELOPMENT-WORKFLOW.md) once accepted.

## Why this exists

The delivery records — [FEATURE-LIST.md](FEATURE-LIST.md),
[PROJECT-TRACKER.md](PROJECT-TRACKER.md),
[TECHNICAL-DEBT-TRACKER.md](TECHNICAL-DEBT-TRACKER.md), and
[slices/SLICE-REGISTRY.md](slices/SLICE-REGISTRY.md) — drift out of calibration
whenever more than one worker edits them at once from divergent bases, or when a
record change is left uncommitted while the code it describes lands separately.
The Flow Dashboard reads these records, so every partial state is visible. The
process is already defined; the failures are adherence failures. These rules make
adherence mechanical.

## Rules

1. **Records land with their code.** The record edits for a slice and the code
   they describe go in the **same commit**. Never leave a record file dirty in
   the working tree across sessions — a half-updated record is the drift.
2. **One integrator owns record commits.** Exactly one role writes and commits
   `FEATURE-LIST.md`, `PROJECT-TRACKER.md`, `TECHNICAL-DEBT-TRACKER.md`, and
   `SLICE-REGISTRY.md`. Others hand the integrator a status delta; they do not
   edit these four files directly.
3. **Parallel autonomous workers stay in their lane.** A long-running
   `claude -p` loop uses its reserved **100–199** slice/feature block (see the
   registry) and **disjoint files**. It never allocates numbers in the primary
   001–099 range and never edits the four record files.
4. **Reserve before you create.** Add the row to
   [SLICE-REGISTRY.md](slices/SLICE-REGISTRY.md) before writing
   `docs/slices/NNN-*.md`. New `F-<n>` ids follow the same reserve-first rule.
   Never rename a shipped id — status lives in the `Status:` field.
5. **Gate before you commit.** Run `scripts/check_record_sync.sh`; it must exit 0
   before any record commit (and belongs in a pre-commit hook). It fails on
   dangling feature anchors, duplicate slice numbers, slices missing from the
   registry, a stale next-free pointer, and malformed feature status.
6. **The board shows committed truth.** The dashboard renders records from
   committed `HEAD` and marks uncommitted record files as in-flight. Do not
   "fix" a perceived desync by editing records to match the dashboard — commit
   the in-flight work (or discard it) so `HEAD` is the truth.

## One-line summary

Reserve the number, do the work, then commit **code + all touched records + a
green `check_record_sync.sh`** as one atomic change — and only the integrator
touches the four record files.
