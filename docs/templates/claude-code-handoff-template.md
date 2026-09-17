# Claude Code Handoff Template

This is the durable, canonical template for an agent-assisted delivery handoff.
Copilot (the orchestration and review layer) fills it in to hand a bounded,
multi-file implementation to Claude Code CLI (the implementation layer). Use it
only after the governing ticket has a recorded decision and the foundation gate
is closed. The authoritative ownership rules live in
[AGENTS.md](../../AGENTS.md) and
[.github/copilot-instructions.md](../../.github/copilot-instructions.md); this
template expresses a handoff, it does not redefine those rules.

## User outcome

<one sentence describing the observable behavior>

## Scope

- In scope: <bounded implementation items>
- Out of scope: <explicit non-goals>

## Repository context

- GitHub issue: <#number or issue URL; use Fixes/Closes/Resolves when this handoff will complete it, otherwise Refs>
- Governing ticket: <relative ticket path>
- Primary phase and slice: <phase / slice id>
- Files Claude Code may create or change: <paths>
- Files to preserve: <paths>

## Public seam

<entry scene, command, API, or other externally observable boundary>

## Safety invariants

- <invariant>

## Acceptance scenarios

1. Given <initial state>, when <action>, then <observable result>.
2. Given <highest-risk state>, when <action>, then <observable result>.

## Validation

<exact commands Claude Code must run and report with exit codes and relevant output>

## Return report

Claude Code must report:

- files changed
- commands run and their results (exact commands and exit codes)
- behavior observed
- known limitations or failures
- any scope deviation requiring Copilot review

## Traceable handoff evidence

A handoff is *traceable* only when all of the following are recorded together in
the slice record and delivery records, so planning → implementation → review can
be reconstructed without guesswork:

1. **Brief** — this filled-in template (GitHub Issue, bounded scope, seam,
   non-goals, validation, required evidence), linked from the slice record.
2. **Change set** — the exact files Claude Code created or changed, matching the
   declared scope. Any file outside the declared scope is an unscoped edit and
   is flagged in review, never silently accepted.
3. **Validation evidence** — the focused command, its expected pass signal, and
   the machine-readable artifact (for the GUT suite,
   `build/validation/validation-summary.json` plus `build/validation/gut.xml`)
   with the exit code.
4. **Review outcome** — Copilot's scope, safety, and specification review,
   including any liability opened in `TECHNICAL-DEBT-TRACKER.md` for a gap found.
5. **Feature synchronization** — the `FEATURE-LIST.md` and `PROJECT-TRACKER.md`
   updates made in the same change set (Jidoka: stale status is a defect).

If Claude Code hits a session limit, timeout, or validation failure, the slice
is `blocked` or `awaiting evidence`; completion is never inferred from files
appearing in the tree.
