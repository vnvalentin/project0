# Issue #1432: GitHub API and Project rate-limit resilience

## Goal

Prevent delivery work that needs GitHub Project V2 from reaching expensive
implementation or validation before API availability is known. Keep REST issue
operations distinct from GraphQL-backed Project operations, capture failures,
and stop without retry loops or false synchronization claims.

## Delivery placement

- Governing issue: #1432, Technical Debt.
- Project: Project0 Delivery #2; Outcome G, In Progress, Evidence Missing,
  Blocked No.
- Milestone/slice group: none; this is cross-cutting delivery-process work with
  no committed product milestone.
- Related issues: #1431 (observed blocker), #1216 (prior but distinct budget
  exhaustion case).
- Branch: `fix/1432-gh-api-resilience`, from latest `origin/main`.

## Public seam and hypothesis

The public seam is the repository's GitHub delivery procedure plus a reusable
`scripts/github_api_guard.py` command used for GraphQL preflight and guarded
GitHub CLI operations, including `gh project`.

Hypothesis: an early single-query GraphQL capability check, scoped Project
operations, direct REST for issue endpoints where available, and fail-fast
evidence capture will expose API failures before costly work and prevent wasted
retries. A mocked subprocess test can disconfirm this cheaply by asserting exact
call counts, exit behavior, quota snapshots, and retained failure evidence.

## BDD scenarios

- Given Project V2 work is required and REST reports a nonzero GraphQL budget,
  when preflight runs, it issues exactly one minimal read-only GraphQL query and
  records the REST quota plus GraphQL result.
- Given REST reports no GraphQL points, when preflight runs, it stops before
  issuing GraphQL and records the reset metadata.
- Given GraphQL rejects a minimal query while REST reports points remaining,
  when preflight runs, it preserves the response and exits nonzero without retry.
- Given a `gh project` command fails, when run through the guard, it executes
  once, records exact stderr/exit and one REST quota snapshot, and does not
  report synchronization success.
- Given issue data has a REST endpoint, the documented process uses REST rather
  than spending GraphQL points for that operation.
- Given Project recovery, completion still requires a targeted field readback;
  a successful mutation alone is not synchronization evidence.

## TDD and implementation sequence

1. Add mock-based tests for preflight success, exhausted primary quota,
   GraphQL rejection with points remaining, malformed API responses, and
   one-shot Project CLI failure evidence.
2. Add the Python guard to satisfy the tests. It will make subprocess calls
   without a shell, never auto-retry, avoid logging credentials, and write
   machine-readable evidence on both success and failure.
3. Document when/how to run preflight, wrapping `gh project`/GraphQL calls,
   REST use for issue operations, stop-and-record behavior, and targeted
   readback in `AGENTS.md` and `.github/copilot-instructions.md`.

## Non-goals

- Bypass Project #2, weaken record synchronization gates, or treat REST issue
  updates as a substitute for Project fields.
- Claim a GitHub-side root cause without evidence.
- Add dependencies or change product runtime behavior.
- Automatically sleep, poll, or retry an unavailable API.

## Validation and evidence

Run the Linux-tooling ownership preflight before executing checks. The focused
check is `python3 -m unittest scripts.test_github_api_guard`; also run Python
compile validation, `scripts/check_record_sync.sh`, the full GUT gate, and
required review/PR gates. Capture command, host, revision, result, and artifact
paths on #1432. Project acceptance requires verified Project #2 readback after
recovery.

## Rollback

Revert only this issue's helper, tests, and documentation changes through its
PR. They have no product-runtime or persistent-data effects. Preserve issue
evidence and do not clear Project fields as part of rollback.