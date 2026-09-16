# Slice 094 - Reality dashboard truthfulness and delivery-record reconciliation

Status: **delivered**

Phase: 7 (Delivery workflow capabilities), advancing [F-025](../FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard).

## User outcome

The Reality page presents a trustworthy project snapshot: delivered slices count as delivered, repeated feature headings do not inflate totals, overall completion is weighted by tracked work items, and the page identifies the committed revision and hidden working-tree changes.

## Scope and non-goals

In scope: `dashboard/app.py` parser and executive Reality view; deduplication of feature ids; recognition of both `100% complete` and `delivered` slice labels; item-weighted overall completion; commit provenance and uncommitted-change warning; reconciliation of stale Phase 1 and Phase 8 phase-table statuses; synchronized delivery records.

Out of scope: changing the authoritative completion meaning of Phase 13, editing unrelated working-tree artifacts, adding dashboard write operations, or changing the Linux mirror deployment.

## Public seam

- `dashboard.app.feature_cards(reader)` returns unique feature cards.
- `dashboard.app._slice_done(status)` classifies tracker completion labels.
- `dashboard.app.phase_progress_map(tracker)` parses phase item counts.
- `dashboard.app.executive_model(reader)` returns the Reality metrics.
- `dashboard.app.render_exec(view)` displays source revision and stale-work provenance.

## Safety invariant

The dashboard remains read-only. Committed Reality view reads `git show HEAD:` records, while the explicit Working tree view reads live files. It must never present uncommitted work as committed truth, and it must not mutate project records or runtime state.

## SDD

The defect was in the dashboard's interpretation boundary, not in the delivery data: newer slice records use `delivered`, the feature list contains repeated headings for one stable id, and phase percentages have explicit item counts. The smallest correction is to normalize those existing representations at the parser boundary and expose the source revision in the view.

## BDD / TDD

- Given a slice status containing `delivered`, the slice is counted as complete.
- Given repeated headings for one feature id, the feature appears once.
- Given phase item counts, overall completion equals completed items divided by total items.
- Given uncommitted record changes in committed view, the source revision and warning are visible.
- Given the reconciled tracker, Phase 1 and Phase 8 show `done` consistently with their 100% work indexes.
- Given the existing record set, `executive_model(read_repo_file)` calculates overall completion from phase item counts, partitions every unique feature into exactly one stage, and returns no duplicate feature ids.

## Validation

Focused command:

```text
$env:PROJECT_ROOT="d:\code\project0"; python -c "import importlib.util; spec=importlib.util.spec_from_file_location('dash','dashboard/app.py'); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); model=m.executive_model(m.read_repo_file); cards=m.feature_cards(m.read_repo_file); phases=m.phase_progress_map(m.read_repo_file('docs/PROJECT-TRACKER.md')); done=sum(p['done_items'] for p in phases.values() if p['done_items'] is not None); total=sum(p['total_items'] for p in phases.values() if p['total_items'] is not None); assert model['overall'] == round(done / total * 100); assert len(model['done']) + len(model['active']) + len(model['not_started']) == len(cards); ids=[f['id'] for f in cards]; assert len(ids) == len(set(ids))"
```

Expected pass signal: command exits 0 with all assertions passing.

Additional validation: `scripts/check_record_sync.sh` exits 0. The focused result is represented by the command exit code; record-sync output is the repository's machine-readable-equivalent shell gate for this documentation/dashboard slice. Full GUT is not required for the Python-only dashboard change, but remains a no-regression gate before merge.

Full-suite gate status: blocked in the current Windows environment. Git Bash ran
63/64 scripts with 341 passing, 12 failing, 77 risky/pending, and 1,182
assertions; `build/validation/gut.xml` was emitted. The failures were in the
unrelated SQLite/integration and Windows GDExtension/client paths, and the
SQLite script was skipped after a parse/cache error. The WSL invocation failed
before starting because the Bash service returned `Bash/Service/E_UNEXPECTED`.
No GDScript files were changed by this slice.

## Review outcome

The change is scoped to the dashboard parser/view and synchronized records. Phase 13 remains at 0 of 3 because its tracked feature/debt items are not all done; delivered implementation slices alone do not close that phase exit gate.

## Root-cause learning

Observed: the Reality page understated shipped work and showed contradictory source state.

Hypothesis and check: the parser recognized only `100% complete`, counted duplicate feature headings, averaged phase percentages equally, and omitted source provenance. Running the executive model against the records discriminated these cases: delivered slices were excluded, duplicate ids existed before normalization, and phase item counts were available.

Root cause and countermeasure: status-label drift and duplicate record headings crossed the dashboard parsing boundary without normalization. `_slice_done`, unique-id tracking, item-weighted aggregation, and provenance output now make those representations explicit.

Regression evidence: the focused model assertions pass with the phase-weighted
overall value, a complete unique-feature partition, and zero duplicate feature
ids; `scripts/check_record_sync.sh` passes with 0 errors. The full GUT gate
remains blocked by the recorded unrelated failures.

Remaining limitation: committed view still reflects the dashboard source checkout's HEAD; unmerged branches are intentionally not presented as committed reality. The view now identifies that limitation and links to Working tree mode.
