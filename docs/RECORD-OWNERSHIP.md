# Record Ownership Rule (draft)

Status: **draft** for review. Fold into [AGENTS.md](AGENTS.md) and
[DEVELOPMENT-WORKFLOW.md](DEVELOPMENT-WORKFLOW.md) once accepted.

## 2026-09-20: Features and Slices moved to GitHub issues

`FEATURE-LIST.md` and `docs/slices/*.md` (including `SLICE-REGISTRY.md`) are now a
**frozen historical archive** — the record of everything delivered before this
date. Do not add new entries to them. Going forward:

- A **Feature** is a GitHub issue labeled `Feature`, with a `Parent goal: #N`
  line in its body when it advances a Goal issue.
- A **Slice** is a GitHub issue labeled `Slice`, with a `Parent feature: #N`
  line in its body when it advances a Feature issue.
- `docs/PROJECT-TRACKER.md` and `docs/TECHNICAL-DEBT-TRACKER.md` are unaffected
  by this change and remain live, committed-file records (see the rules below).

## Why this exists

The delivery records — historically `FEATURE-LIST.md`,
[PROJECT-TRACKER.md](PROJECT-TRACKER.md),
[TECHNICAL-DEBT-TRACKER.md](TECHNICAL-DEBT-TRACKER.md), and
`slices/SLICE-REGISTRY.md` — drift out of calibration whenever more than one
worker edits them at once from divergent bases, or when a record change is left
uncommitted while the code it describes lands separately. The Flow Dashboard
reads these records, so every partial state is visible. The process is already
defined; the failures are adherence failures. These rules make adherence
mechanical. Feature/Slice status now lives on GitHub issues instead, which
removes the number-allocation race for those two record types, but the same
adherence discipline applies to the two records that remain files.

## Rules

1. **Records land with their code.** The `PROJECT-TRACKER.md`/
   `TECHNICAL-DEBT-TRACKER.md` edits for a slice and the code they describe go
   in the **same commit**. Never leave a record file dirty in the working tree
   across sessions — a half-updated record is the drift.
2. **One integrator owns record commits.** Exactly one role writes and commits
   `PROJECT-TRACKER.md` and `TECHNICAL-DEBT-TRACKER.md`. Others hand the
   integrator a status delta; they do not edit these files directly. Feature and
   Slice issues may be created/edited by whoever is doing the work, since
   GitHub issue numbers do not collide the way file-based numbering did.
3. **Parallel autonomous workers stay in their lane.** A long-running
   `claude -p` loop never edits `PROJECT-TRACKER.md` or
   `TECHNICAL-DEBT-TRACKER.md` directly; it hands the integrator a status delta.
4. **Link parent before you create.** When opening a new Slice issue, add
   `Parent feature: #N` in its body; when opening a new Feature issue, add
   `Parent goal: #N` in its body. Never renumber or relabel a shipped issue's
   identity — status lives in the issue's state/labels, not a renamed title.
5. **Gate before you commit.** Run `scripts/check_record_sync.sh`; it must exit 0
   before any `PROJECT-TRACKER.md`/`TECHNICAL-DEBT-TRACKER.md` commit (and
   belongs in a pre-commit hook).
6. **The board shows committed truth.** The dashboard renders `PROJECT-TRACKER.md`/
   `TECHNICAL-DEBT-TRACKER.md` from committed `HEAD` (marking uncommitted record
   files as in-flight) and renders Feature/Slice status live from the GitHub
   issues API. Do not "fix" a perceived desync by editing records to match the
   dashboard — commit the in-flight work (or discard it) so `HEAD` is the truth.

## One-line summary

Feature and Slice status live on labeled GitHub issues with `Parent goal`/
`Parent feature` back-links. `PROJECT-TRACKER.md` and `TECHNICAL-DEBT-TRACKER.md`
remain committed-file records: do the work, then commit **code + those two
records + a green `check_record_sync.sh`** as one atomic change, and only the
integrator touches those two files.
