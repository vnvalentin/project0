# Slice #1431: Acceptance-Gate Membership

- Parent feature: #68
- Milestone: #8, group M8.1 Delivery Traceability
- Branch: `slice/1431-acceptance-gate-membership`
- State: Active; new milestone outcome remains unstarted/unaccepted.

## Hypothesis
An explicit `Membership: acceptance-gate-only` marker can keep a gate visible while preventing an empty gate from being treated as a delivery slice. Unmarked empty groups and malformed membership must continue to warn.

## Scope
Update the milestone description parser, roadmap Bands/detail rendering, dashboard tests, and mapping documentation. M8.2 is explicitly gate-only with an empty Included issues field; #1259 remains external context, not membership.

## Non-goals
No runtime/deployment work, changes to M8.4 acceptance, validation execution, issue statuses beyond #1431's active work state, Windows/client work, or production state.

## Validation
See `validation-plan.json` for Linux-owned suite and dependency selections. Run the focused roadmap regression, all dashboard tests, the required GUT suite, and record-sync check on `192.168.1.254` over SSH.
