# Project0 Flow Dashboard

Read-only local Kanban and Andon dashboard for the authoritative markdown
records in the parent repository.

## Run

From `dashboard/`:

```bash
docker compose up --build
```

Open http://127.0.0.1:8080. Health: http://127.0.0.1:8080/health

The container mounts the repository read-only and has no write endpoint. It
refreshes the tracker files every 15 seconds, so status changes appear without
rebuilding the image.

If port `8080` is already occupied, start the same image on another local
port, for example:

```bash
docker compose run -d --name project0-flow-visual -p 127.0.0.1:18083:8080 project0-flow
```

Then open http://127.0.0.1:18083.
