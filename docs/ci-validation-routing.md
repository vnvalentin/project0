# CI Validation Routing

Governing issue: [#1259](https://github.com/vnvalentin/project0/issues/1259).
Parent: [#1244](https://github.com/vnvalentin/project0/issues/1244).

## Source Contract

Schema version 1. `route` is a Windows **metadata** job, not native acceptance.
It acquires the exact event candidate on Windows and reads live PR metadata
with the read-only GitHub token. An open same-repository PR must target main,
match the event SHA and current main base, and contain that base as an ancestor.
A main push must identify exactly one merged PR and one merge commit whose
first parent is the event's previous main SHA. Missing, ambiguous, stale, foreign
or unsupported identities fail the metadata route.

Independent administrator-owned runner admission, delivered by
[#1265](https://github.com/vnvalentin/project0/issues/1265), authorizes Linux
acquisition before workflow steps. See [the admission contract](ci-runner-admission.md).
The candidate's metadata route is not an authorization authority. Every Linux
validation job depends on `route`, checks out the independently approved source
ref, verifies its exact commit and tree, then requires agreement with the route's
`linux_ref` and committed Git blob digest. The exact candidate remains `windows_ref`.
An unknown candidate requires a separately reviewed, expiring administrator grant;
neither a passing route nor this PR creates that grant.

Linux-only changes use the candidate SHA. A `platform:windows-required` change
may use the approved main baseline only when all tracked inputs except direct
`scripts/*.ps1` files, `docs/validation-ownership.md`, and the reviewed Windows
assets `scripts/client_package_inventory.gd`, `scripts/windows_paired_client.gd`
and `tests/fixtures/windows_client_packages.gd` are byte-identical.
The sorted path/blob map binds additions and deletions as well as modifications.
This narrow exclusion is for Windows tooling, not game/client/native changes.
Changed client/native/export inputs, unknown paths, mixed Linux inputs, symlinks,
submodules and missing Windows labels fail closed. The ownership manifest and
workflow are Linux inputs: changing them cannot be hidden by baseline reuse.

## Container Image Routing

`images.yml` uses independent runner admission before any Linux checkout, not
the candidate-owned metadata route. The three image check names remain on the
assigned okami runner. Denied or missing approval prevents acquisition. The
approved ref and tree are checked before Docker credentials or builds. Manual
and tag grants bind independent approved-main identity and Windows classification;
the candidate cannot reset that classification through an empty label list.

The existing `default` Docker builder is used without creating a builder service.
Credentials live in job-private `DOCKER_CONFIG` under runner temp, initialized
at step scope, and are removed by always-run cleanup only when that job created
the directory. No GitHub cache exporter is requested from the default
Docker driver. Images carry the approved source revision and SHA tag. PRs never
publish. Windows-only candidates build identical approved Linux inputs as
supporting evidence but never publish server images. Linux main/tag/manual
publishing remains; publishing is not deployment.

## Execution And Evidence

All four Linux jobs require runner labels `self-hosted, Linux, X64, okami`,
assigned to `192.168.1.254`. The generic hosted Linux alias is not permission to
move server/Canon execution. Runner prerequisites must already exist; no
dependency installation or fallback host is performed.

Host tools: Python 3, Git, gh for metadata on Windows, Bash, existing service
requirements/pytest, and Docker on okami. GUT uses existing image
`sha256:801341fea24b22777e65e8ad5b38ca306c33e59b4adcdc14c37d8f461b162602`
only for runtime execution; it does not contain Python/Git. Its container has
no network, no capabilities, read-only root, private tmpfs/HOME and no shared
database or dashboard paths. A bounded timeout and exit trap remove only its
uniquely named container. CI checkout state belongs to the runner job.

`routing/plan.json` records candidate, baseline, Linux/Windows refs, input digest,
changed paths, required jobs, expected test files and the evidence limitation.
The artifact name binds the GitHub run ID and attempt. Commands:

```text
python scripts/ci_validation_routing.py plan
python3 scripts/ci_validation_routing.py verify-source --plan <plan.json>
python3 scripts/ci_validation_routing.py seal --job <linux-job> --plan <plan.json>
python scripts/ci_validation_routing.py aggregate --results <download-directory>
```

Required jobs remain ownership, godot, records, python and launcher. Coverage
units are the existing required test **files/scripts**, not a claim of atomic
test-case inventory. XML failures/errors/skips and omitted files reject sealing.
Ownership uses its real JSON reports, including independent admission tests, and
requires positive execution counts with no failures, errors or skips. Its static
inventory report is supporting evidence, not test execution. Record checks use
successful command logs; zero errors with retained warnings remains success.
The unconditional acceptance job additionally rejects any failed/skipped job.
Artifact hashes are recomputed from downloaded bytes, not accepted on assertion.
CLI failures emit `routing/report.json`; original job artifacts upload on failure.

## Windows Handoff

The existing Windows runner still executes the native tests. CI captures its
real `go test -json` stream, independently collects Go test names/source files,
and retains the fixture lifecycle completion signal and runner summary. The
shared sealer rejects missing, failed, skipped or uncollected execution before
writing `build/validation/windows_launcher/result.json` for the exact
`windows_ref`. The workflow uploads that report and proofs as
`result-launcher-<run_id>-<run_attempt>`. The result schema is:

```json
{
  "schema_version": 1,
  "candidate": "<plan.candidate>",
  "source_ref": "<plan.windows_ref>",
  "input_digest": "<plan.input_digest>",
  "status": "success",
  "skipped": 0,
  "tests": ["<every actually executed plan.expected_tests.launcher entry>"],
  "artifacts": {"proof.json": "<SHA-256 of the uploaded bytes>"}
}
```

Coverage is derived from executed tests and native collection metadata, never
copied from the plan into a success record. Source files are the compiled inputs
of packages whose selected test set actually ran and passed. Only the existing
`TestExperiment1100RealEngine` opt-in may be unselected; it is reported as
unevaluated, not passed. Every other collected test must be selected, and every
skipped selected test rejects the report. The
aggregate verifies omission disclosure against the hashed native inventory.
The summary alone is insufficient. Additional Windows client/paired gates require
their own evidence; this report does not claim gameplay acceptance.

Full GUT is supporting Linux evidence, never Windows or paired acceptance.
Retain accepted diagnostic fingerprints and debts #1189/#1190; no global clean
claim. Rollback only #1259's owned routing, workflow, report and ownership
metadata changes, never runtime state. Rollback
restores the unsafe checkout route, so Windows publication must stop first.
