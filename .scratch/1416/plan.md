# CI PR Metadata Routing - #1416

GitHub issue: #1416
Milestone/slice: None; cross-cutting CI maintenance with no committed product outcome.

## Goal

Read pull-request metadata without GraphQL while preserving the platform-owned source admission checks.

## Public seam and contract

`scripts/ci_validation_routing.py::metadata_from_event` resolves the current PR after validating the candidate checkout and approved base. The REST response must preserve the candidate head SHA, base SHA/ref, label list, open state, and same-repository check. Any missing, stale, foreign, forked, closed, wrong-base, or mismatched identity remains fail-closed.

## BDD

- Given a current open PR targeting `main` in this repository, when metadata is classified, then its exact head/base identities and labels are returned for routing.
- Given a closed, forked, foreign, stale, or wrong-base PR, when metadata is classified, then classification rejects it before source routing.
- Given the REST request fails or returns incomplete metadata, when metadata is classified, then classification fails closed and does not use GraphQL as a fallback.

## Hypothesis and discriminating check

The classifier calls `gh pr view`, a GraphQL-backed command. Local `gh pr view 1403` returned a GraphQL rate-limit error; the exact Actions stderr is unavailable, so this is a plausible cause, not a confirmed root cause. Replace the metadata request with the REST `gh api` endpoint and assert the exact call plus mapped identity in the focused unit test. A same-head CI rerun must then pass route classification and execute its required gates.

## Scope and non-goals

Change only the PR metadata lookup and its routing tests. Do not weaken identity checks or alter the workflow gates. No change to PR #1403's product evaluator, runner migration, or the separate #850/#951 work.

## ADR rationale

No ADR is needed: this replaces one GitHub CLI metadata transport with its REST equivalent and preserves the existing routing contract, ownership boundary, and workflow policy. It introduces no new architecture or persistent data.

## Validation and rollback

Run the focused `scripts/test_ci_validation_routing.py` suite on Linux host `192.168.1.254` under the `linux-tooling` owner with `python3`, using `.scratch/1416/validation-plan.json`. The host has no `python` executable. Then use the exact-head Actions run to verify source identity and actual test coverage. Revert the branch/PR to roll back; no product runtime state is touched.