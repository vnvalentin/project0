# Project0 Master Roadmap

Read-only roadmap for the technology-neutral master game vision. The `/roadmap`
page presents the live GitHub backlog as two views: a collapsible layered
Hoshin-to-Experiment story map and a focused next-work branch. The page is not
an implementation status claim and does not choose storage, model, messaging,
or map-builder technology.

## Run

From a development checkout's `dashboard/`:

```bash
docker compose up --build
```

Open http://127.0.0.1:8080. Health: http://127.0.0.1:8080/health

The dashboard is localhost-only by default. To make it reachable from other
machines on the local LAN, bind Docker to this host's LAN address (rather than
all interfaces):

```bash
DASHBOARD_BIND_ADDRESS=192.168.1.254 DASHBOARD_HOST_PORT=18083 docker compose up --build -d
```

The resulting LAN URL is http://192.168.1.254:18083. The host firewall must
permit TCP `18083` on the LAN interface. To expose the service on every host
interface, explicitly set `DASHBOARD_BIND_ADDRESS=0.0.0.0`; this is not the
default.

The master roadmap page is available at
http://192.168.1.254:18083/roadmap. The root URL serves the same page for
backward compatibility.

The container mounts the repository read-only. Page refreshes every 60 seconds
read a local snapshot, not GitHub. The only POST endpoint requests a cache
refresh; it does not change GitHub records. The full backlog uses `tbp:hoshin`, `tbp:theme`,
`tbp:feature`, `tbp:epic`, and `tbp:experiment` labels plus their parent links.
The next-work view follows an in-progress branch; when none exists, it clearly
labels the deterministic ready-to-pull branch as proposed rather than active.

One background worker reads GitHub issues and milestones from `GITHUB_REPO`
(default `vnvalentin/project0`) through `gh api`. Automatic refresh runs every
`GITHUB_ISSUE_CACHE_SECONDS` (default `1800`, or 30 minutes). The **Refresh now**
button requests an immediate asynchronous refresh; simultaneous requests share
the current refresh. Unchanged pages are conditionally requested with ETags.
Neither browsing nor refresh-status polling contacts GitHub.

The last successful snapshot and ETags are stored atomically at
`GITHUB_CACHE_PATH` (default `/cache/github-feed.json`) in the dedicated Compose
cache volume. Restarting loads that snapshot and preserves its next scheduled
refresh time. Do not run multiple dashboard instances against one cache volume.
Tokens are supplied through `GITHUB_TOKEN` or `GH_TOKEN`, never written to the
snapshot. The image includes `gh`; no interactive authentication is performed.

GitHub remains authoritative. The toolbar displays last successful update,
refresh progress and stale/failure state. A failed issue or milestone fetch
preserves the entire previous snapshot and does not immediately retry; manual
refresh remains available. Before the first successful refresh the source is
explicitly unavailable. The cache is disposable operational data, not a second
delivery record. Removing its volume forces a cold full fetch. The markdown
vision remains the local source of truth. The `/tracker` page is retained only
as a read-only viewer of the frozen `docs/PROJECT-TRACKER.md` archive; it does
not project active status or enforce tracker parity.

`GET /api/github/status` returns local freshness/progress and counts, not issue
bodies. `POST /api/github/refresh` requires `X-Dashboard-Refresh: 1` and rejects
cross-origin browser requests; the button sends this automatically. It returns
`202` without waiting for GitHub. Existing LAN-only exposure is unchanged.

The `/delivery` page is the local operational view for active GitHub Issues. It
shows the active delivery table and groups work by Outcome and Phase, with
milestones, blocked state, evidence, parent issue, and assignee visibility.
These fields are projected from issue labels, milestones, assignees, and
structured body lines, so the view does not depend on GitHub Project #2 custom
field access.

## Milestone Slice Mapping

GitHub milestone titles use `Milestone N: Outcome`. Roadmap views order these
numerically by the displayed milestone number, not GitHub's immutable milestone
ID. Existing compact `M0` titles remain supported, and slice-detail URLs continue
to use the original GitHub ID.

M0 has the approved groups M0.1 Standalone Entry, M0.2 Movement and Traversal,
M0.3 Solo Combat, and M0.4 Mind versus Tool. M1 has M1.1 Shared Exploration and
M1.2 Co-op Combat. Their descriptions and issue memberships live in GitHub, not
in a hardcoded dashboard list. Launcher milestones remain explicitly paused;
their display numbers do not authorize resuming work.

The default Roadmap at `/roadmap` opens Bands and reads delivery Slice groups
from each GitHub milestone description. It does not infer membership from
issue labels or parent links. The backlog tree is available through the
**Backlog** link at `/roadmap?mockup=backlog`. The explicit Bands URL
`/roadmap?mockup=delivery-a` still works; Timeline (`delivery-b`) and Gantt
(`delivery-c`) remain available through the view switcher. Hybrid
(`delivery-d`) combines milestone order, target dates, status, slice completion,
and expandable Bands detail.

```markdown
Outcome: The measurable milestone delivery outcome.

## Slice Mapping
### Slice A1: Trusted First Install
Outcome: The contribution this group delivers.
Included issues:
- #123
- #456
Complete when: The required acceptance proof.
Dependency: Prerequisites for this work.
Context: #789 Parent context, cited on the first Slice it relates to; not a member.
Outcome evidence: https://example.test/accepted-validation

## Required Scope Awaiting Slice Definition
- Additional required work whose grouping is not yet agreed.
```

`## Slices` is also accepted. Each group requires a unique identifier, title,
outcome, completion criterion, and explicit `- #number` members. Fenced examples
and references outside `Included issues` do not establish membership. Missing
issues, duplicate membership, and issues assigned elsewhere are displayed as
mapping warnings and keep the affected group New. Issues assigned to the
milestone but outside its groups appear as unmapped work. A `## Shared Context`
section is not allowed (#1400): it is shown as a mapping warning and its issues
count as unmapped. List a shared issue on the first Slice it relates to, under
`Included issues:` when it is assigned to the milestone, otherwise in `Context:`.

Groups default to delivery membership and require at least one included issue.
An explicit `Membership: acceptance-gate-only` classifies a group as an
acceptance gate, not delivery work. It must include an empty `Included issues:`
field, remains visible with its own gate label, and is excluded from delivery
completion counts. It cannot contain delivery issues. Unknown membership values
and malformed gate-only groups fail closed with mapping warnings. Context
references remain informational and do not create issue membership.

Each card and defined group shows issue activity independently: closed/total,
active, and blocked counts. These are issue counts, not accepted-outcome
percentages. Milestone activity includes assigned issues outside defined groups;
Unscheduled backlog shows issues without a milestone. Group activity deduplicates
members and excludes missing or foreign-milestone references. Closed issues
never count active or blocked. Activity recognizes existing status labels and
explicit current declarations such as `Status: In Progress` at the start of an
issue or `In progress: ...` under level-two `## Status` or `## Delivery Status`
headings. Quoted, fenced, indented-code, checklist, nested historical headings
and general prose do not establish activity. GitHub
Project-only status and issue comments are not read by this projection.

Expanded lists show only linked issue numbers and one Closed, Open, or Active
badge. Closed takes precedence over stale activity; blocked information remains
in aggregate counts and the badge's accessible label and tooltip. Issue titles
are available through link tooltips and accessible names. Slice descriptions
are reached through **View Slice description** at
`/roadmap?milestone=<number>&slice=<identifier>`, scoped to that milestone.
The details page shows Outcome, Completion description, Dependency, and any
recorded outcome evidence, with a **Back to roadmap** link. Missing or ambiguous
identifiers and unavailable source data remain explicit. New/Ready/Doing/Done
badges and the per-Slice readiness explanation are not displayed in Bands;
the underlying acceptance calculation is unchanged.

The separate Slice delivery counter counts accepted groups, not individual
issues. No group definitions displays `Outcome acceptance: not defined`, while
issue activity remains visible. Open members need explicit
readiness or the existing TBP Theme/Feature/Epic definition checks; missing
readiness and blockers keep a group New. Doing requires in-progress work with
the remaining members ready or closed. All members closed without linked
`Outcome evidence:` is Doing, awaiting evidence; with that link the group is
Done. The link records human acceptance evidence, not automated proof that a
remote artifact passed. No definitions means zero defined Slices, not inferred
completion. Unresolved milestone scope remains visible even if all defined
Slices are Done. This projection never changes GitHub records.

## Host deployment under `/apps/project0/dashboard`

The production host layout is self-contained and does not depend on a user's
home directory:

- `/apps/project0/dashboard/docker-compose.yml` — the compose project.
- `/apps/project0/dashboard/Dockerfile` and `roadmap.py` — the dashboard image
  source/fallback.
- `/apps/project0/dashboard/repo` — a dedicated clone of `origin/main`, mounted
  read-only into the container at `/repo`.

Install or refresh the app directory from a clean checkout:

```bash
sudo mkdir -p /apps/project0/dashboard
sudo rsync -a dashboard/ /apps/project0/dashboard/
sudo git clone https://github.com/vnvalentin/project0.git /apps/project0/dashboard/repo
sudo install -m 644 project0-flow-mirror-sync.service /etc/systemd/system/
sudo install -m 644 project0-flow-mirror-sync.timer /etc/systemd/system/
sudo systemctl enable --now project0-flow-mirror-sync.timer   # fetch + reset --hard origin/main every 2 min
cd /apps/project0/dashboard
DASHBOARD_BIND_ADDRESS=192.168.1.254 DASHBOARD_HOST_PORT=18083 \
  docker compose up --build -d --force-recreate
```

`DASHBOARD_REPO_SOURCE` defaults to `./repo`, so the compose file works from
`/apps/project0/dashboard` without extra environment. A host-local `.env` can
override it for development. `GITHUB_REPO` can point the issue feed at a
different repository if the tracker is forked. The sync unit also normalizes
file permissions to world-readable, because this host's `umask` (077) otherwise
writes checkouts as `0600`, which the container's `nobody` user cannot read.

If port `8080` is already occupied, start the same image on another local
port, for example:

```bash
docker compose run -d --name project0-flow-visual -p 127.0.0.1:18083:8080 project0-flow
```

Then open http://127.0.0.1:18083.
