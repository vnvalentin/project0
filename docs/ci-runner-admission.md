# CI Runner Admission

Owner: [#1265](https://github.com/vnvalentin/project0/issues/1265), prerequisite
to [#1259](https://github.com/vnvalentin/project0/issues/1259).
Decision: [ADR 0012](adr/0012-independent-ci-admission.md).

## Goal And Closure

The candidate cannot authorize its own Linux source acquisition or publication.
Close #1265 only with evidence for all of these:

1. Root-owned, fingerprinted policy and an independent expiring grant are needed
   before Linux steps; candidate-owned policy files and approval claims fail.
2. Changed source/workflow/ref/event/host/job, stale or ambiguous grants, missing
   checks and direct Windows execution are rejected. Windows-baseline policy
   controls retain exact baseline authority and identical Linux input digests.
3. A real denied runner job cannot continue via `if: always()` or override the
   administrator hook/context through job environment variables. A control runs.
4. Protected main retains all eight required check identities and normal PR
   delivery; no admin bypass, direct push or image publication shortcut is used.
5. Focused checks, full GUT, record sync, actual CI and review pass on exact
   source, and installation/owned-resource cleanup are verified.

## Installation Contract

The supported runner is okami (id 21), Linux 192.168.1.254, service
`actions.runner.vnvalentin-project0.okami.service`, root `/data/actions-runner`.
The tested version is 2.337.0. Do not install under a candidate checkout or use
candidate-provided paths, interpreters, dependency installation or approval data.

Install reviewed `ci_runner_admission.py` and `ci_runner_job_started.sh` below
`/opt/project0-ci/admission/`, root-owned and not group/other writable. Install
`/etc/project0-ci/admission.json` with the same ownership restrictions and its
`gate_sha256` equal to the installed Python bytes. Parent directories must also
be root-owned, not writable by the runner, and not symlinks.

Configure the runner administrator's `ACTIONS_RUNNER_HOOK_JOB_STARTED` to the
installed launcher, not a workflow environment value. Pin runner binaries and
disable automatic runner replacement while this ABI is relied on. Preserve the
previous configuration; change/restart only an idle runner. A version upgrade
requires the negative live probes before updating the pin.

The launcher is only supported directly under the verified pinned `Runner.Worker`
parent. It is not a general shell wrapper. Missing policy, permission/hash errors,
expired/unknown grants or policy timeouts terminate that job worker, not the
listener or unrelated processes. Read denials from the `project0-ci-admission`
journal tag and correlate run/attempt/job/source with GitHub job state.

## Grant Contract

Schema 1 policy contains `repository: vnvalentin/project0`, `runner: okami`,
`gate_sha256`, and `approvals`. The maintainer binds each grant to an exact
GitHub execution SHA/ref, workflow ref/SHA, event, job set, expiry, source ref/tree,
Linux platform, Windows-required classification, approval issue and retained
check set. Obtain these from reviewed immutable source and GitHub metadata.
Never copy a candidate's success flag or proposed Linux ref as authority.

`direct-source` requires source ref equal to the execution SHA or the exact bound
PR head SHA and rejects Windows classification. `approved-ref` rejects both of
those Windows identities and is for a separately reviewed Windows-safe baseline
consumer: baseline and authority refs equal the Linux source, candidate and
source Linux input digests match, and image publication is forbidden. A grant
must not claim this contract unless the exact workflow actually uses it.
Manual/tag source grants additionally require independent approved-main identity.
These are authorization constraints, not runtime or package acceptance claims.

All required checks are retained. There is no automatic policy update from a CI
artifact. During bootstrap, an authorized maintainer installs each exact,
reviewed grant outside the candidate context; an unknown candidate is denied
even if its own classifier reports success. Keep Windows publication blocked
until #1259's source/report integration is delivered and validated.

## Evidence And Rollback

Retain policy/gate SHA256, runner binary pins, before/after configuration, source
tree, test JSON/XML/logs, CI run/job links, journal denials and cleanup records.
Do not record credentials or the runner credential files. A deliberately failed
negative-control job is not a failed product test or a green CI delivery gate;
its harness must report the expected denial and successful control explicitly.

Rollback restores only this owned admission configuration from its recorded
backup while the runner is idle. Stop Windows publication first: removing the
gate restores the old unsafe acquisition boundary. Do not remove main protection
or waive checks to make delivery easier. Preserve approvals and denial evidence;
application services, databases, Windows worktrees and packages are unrelated.