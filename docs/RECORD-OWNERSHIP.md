# Record Ownership Rule
Status: **accepted**. GitHub is the single active source of truth.

## 2026-09-23: All active delivery moved to GitHub
`FEATURE-LIST.md` and `docs/slices/*.md` (including `SLICE-REGISTRY.md`) are now a
**frozen historical archive** — the record of everything delivered before this
date. Do not add new entries to them. Going forward:

- Delivery is **Milestone -> named slice groups -> linked GitHub issues**.
   The milestone description's `## Slice Mapping` owns each group's Outcome,
   Included issues, Complete when and Dependency. Its linked issues carry work,
   acceptance evidence, owner, blockers and resolution.
- Issue types/labels describe the work, not automatic delivery levels. Preserve
   strategic Feature/Goal and existing Slice/Feature parent links where applicable;
   an issue labeled `Slice` is distinct from a milestone's named slice group.
- Technical Debt is a GitHub issue with classification, impact, owner, root cause
   or unresolved hypotheses, remediation and validation criteria. Link affected
   issues/groups; assign a milestone only when remediation is committed.
- `docs/PROJECT-TRACKER.md`, `docs/TECHNICAL-DEBT-TRACKER.md`, and the other
   Markdown records are frozen historical or explanatory archives.
- GitHub Project `Project0 Delivery` (#2) owns the visible operational fields:
   Outcome, Milestone, Status, Evidence, Blocked, owner, and applicable parent
   relationships. Phases are retired; existing Phase fields are legacy metadata,
   not prerequisites or sequencing authorities. Their removal is separate work.

See [Milestones, slice groups, and linked issues](DEVELOPMENT-WORKFLOW.md#milestones-slice-groups-and-linked-issues)
for the current grouping, issue and Technical Debt contracts. Strategic issue
relationships remain reference context, not a replacement delivery ladder.

## Why this exists

The former file records drifted whenever work and status were changed in
different places. Keeping a live tracker beside GitHub made the source of truth
ambiguous. Issue bodies, native issue state, labels, parent links, Project
fields, milestones, and linked evidence are canonical; repository Markdown is
context only.

## Rules

1. **Issue first.** Create or identify the governing GitHub issue before code.
   Put the current condition, target outcome, exit criteria, non-goals,
   evidence, applicable parent links and milestone/slice mapping in the issue
   body, or explain why the work is cross-cutting or uncommitted.
2. **Project visible.** Add active issues to Project #2 and populate Outcome,
   Status, Evidence, Blocked, owner, and applicable parent relationships. Assign
   a Milestone only for committed delivery work; keep its slice mapping consistent
   with included issue membership. Do not require a new Slice Project field.
3. **Preserve relationships.** Record applicable native parent/child links and
   body references; retain `Parent goal: #N` and `Parent feature: #N` where they
   express an actual relationship. Do not create wrapper issues or reparent
   existing records solely to make their labels resemble the delivery hierarchy.
4. **Keep stable identifiers.** GitHub assigns new issue numbers. Preserve
   milestone IDs, issue IDs and slice-group identifiers; do not allocate new work
   in frozen archives or rename records merely to encode their status.
5. **Validate the active system.** Run focused tests and the full validation
   suite. `scripts/check_record_sync.sh` checks historical links and issue
   traceability; it does not require tracker status parity.

## One-line summary

GitHub milestones commit outcomes, their named slice groups organize delivery,
and linked issues own work and evidence. Project #2 shows operational state;
explicit dependencies determine ordering. Issue closure alone does not prove a
slice or milestone complete. Repository trackers remain frozen context, never
a second status system.
