# Project0 Flow Dashboard

Read-only local Kanban and Andon dashboard for the authoritative markdown
records in the parent repository.

## Run

From `dashboard/`:

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

The container mounts the repository read-only and has no write endpoint. It
refreshes the tracker files every 15 seconds, so status changes appear without
rebuilding the image.

If port `8080` is already occupied, start the same image on another local
port, for example:

```bash
docker compose run -d --name project0-flow-visual -p 127.0.0.1:18083:8080 project0-flow
```

Then open http://127.0.0.1:18083.
