---
status: superseded
---

# Independent CI source admission

> Superseded by the targeted rollback in #1269. The exact-grant design denied
> unreviewed source correctly, but its per-run administrator ceremony caused
> deterministic failures for ordinary PR and label activity. Hosted Linux and
> image jobs now consume the metadata route directly; branch protection and the
> eight required checks remain in force. The implementation and evidence below
> are retained as historical security context.

Under [#1265](https://github.com/vnvalentin/project0/issues/1265), CI acquisition
authority lives outside the candidate checkout. Protected-main policy code is
installed in root-owned paths on okami; a root-owned, expiring ledger approves
exact source, workflow, event and job identities. A candidate-generated plan is
not an admission grant. Main requires PRs and the eight existing checks,
including administrators, without force-push or deletion.

## Context

The previous routing workflow ran its candidate's classifier and verifier.
That was circular authority. A live runner 2.337.0 probe also established that
an ordinary nonzero job-start hook does not stop an `if: always()` step:
run 36352800191 executed the forbidden marker after hook failure.

## Decision

The job-start launcher verifies its `Runner.Worker` parent and runs the installed
policy with an isolated Python interpreter and a bounded timeout. A denied or
failed policy check terminates only that verified job worker before candidate
steps can run. Denials are recorded outside the candidate log in the system
journal. The installed runner version/binaries are pinned; upgrades require
requalification of this integration rather than silently assuming hook behavior.

Root-owned policy and gate paths must not be writable or replaceable through
non-root-writable parent directories. Policy binds the installed gate's SHA256.
Grants identify immutable source/workflow SHAs, event, ref, allowed jobs, required
checks and expiry. Direct Windows source is never granted to Linux. A separate
approved-ref contract requires externally verified identical Linux inputs and
the exact approved baseline; this does not itself prove Windows runtime behavior.

Bootstrap grants are installed by the maintainer after source review and
ownership validation, not by a candidate job. This is intentionally stricter and
more manual than the former self-approval. Candidate workflow changes require a
new independent grant. Missing, expired, ambiguous or mismatched grants deny.
The regular routing/report integration remains owned by #1259.

## Consequences

- Runs 36353352437 and 36354789567 prove hard denial and resistance to job-level
  hook/context spoofing, with successful control jobs and restored runner state.
- A killed worker may not upload its job log. Journal/audit evidence and GitHub
  job state are required; missing evidence is not a passing zero count.
- This is admission control, not a sandbox against already-approved code, host
  administrators, a compromised runner service or compromised GitHub itself.
- Explicit grants add operator work and can expire before a retry. Regranting
  requires the same identity/ownership checks, never a permissive default.
- Installation and main protection alone do not close the issue: policy tests,
  full validation, real CI, review, activation readback and cleanup are required.