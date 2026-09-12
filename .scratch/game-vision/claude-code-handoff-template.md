# Claude Code Handoff Template

Use this only after the relevant Wayfinder ticket has a recorded decision and
the foundation gate is closed.

## User outcome

<one sentence describing the observable behavior>

## Scope

- In scope: <bounded implementation items>
- Out of scope: <explicit non-goals>

## Repository context

- Governing ticket: <relative ticket path>
- Primary phase: <phase>
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
- commands run and their results
- behavior observed
- known limitations or failures
- any scope deviation requiring Copilot review