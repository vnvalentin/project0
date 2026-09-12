Type: task
Status: resolved
Blocked by: 01

## Question
What is the smallest read-only Docker dashboard that makes the current Project0 Kanban board, Andon signals, phase/slice status, and required human actions visible without requiring the user to open markdown files?

## Decision boundary
- Serve a local web dashboard from a Docker container.
- Read the repository's authoritative `PROJECT-TRACKER.md`, `FEATURE-LIST.md`, `TECHNICAL-DEBT-TRACKER.md`, and `PROCESS-MAPS.md` at request time or on refresh.
- Show Kanban columns, current cards, phase status, open technical debt/Andon signals, active Claude/handoff state if discoverable, and an explicit action-required panel.
- Provide read-only links or source excerpts; do not mutate tracker files from the dashboard.
- Keep the dashboard independent of Godot runtime and game server state in this first slice.
- Include a reproducible Dockerfile/compose launch and a health endpoint.

## Non-goals
- Authentication, remote/public deployment, tracker editing, issue creation, live Godot telemetry, or replacing the authoritative markdown records.

## Acceptance evidence
- `docker compose up --build` serves the dashboard locally.
- Kanban, Andon, phase, and action-required views render from current repository records.
- Changing a tracked status and refreshing changes the read-only dashboard view.
- Health endpoint returns success.
- No write endpoint or dashboard action mutates repository files.

## Handoff workflow
Copilot owns the dashboard scope and acceptance criteria. Claude Code CLI owns implementation and container validation. Copilot reviews the rendered dashboard and Docker evidence before any remote deployment decision.

## Answer

Implemented directly under `dashboard/` as a read-only Python standard-library
web service. Docker Compose builds the service, mounts the repository at
`/repo` read-only, and exposes the dashboard on `127.0.0.1:8080`. The UI reads
the authoritative tracker and debt markdown on every request, presents Kanban
columns, phase status, Andon/debt signals, and an action-required panel, and
refreshes the browser view every 15 seconds. `/health` returns JSON success.

No dashboard endpoint writes repository files, and the container does not
depend on Godot, the game server, or Claude Code.

## Validation

- `python3 -m py_compile dashboard/app.py`: passed.
- Docker Compose build/runtime validation: performed separately after the
	dashboard files were created.
