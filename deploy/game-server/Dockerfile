# Reproducible OCI image for the authoritative Project0 Godot game server.
# Runtime boundary per .scratch/container-platform/issues/01-runtime-boundary-and-container-adapter.md:
# pinned Godot 4.3 headless, non-root, UDP 9999, baked import cache, graceful
# shutdown via tini. Runs `server/server_main.gd` exactly like the native
# systemd unit (scripts/project0-server.service) does.

FROM debian:bookworm-slim

# Pinned Godot runtime (provenance = the official 4.3-stable release tag).
ARG GODOT_URL=https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
ARG GODOT_BINARY=Godot_v4.3-stable_linux.x86_64

ENV DEBIAN_FRONTEND=noninteractive

# Godot headless needs fontconfig for its text server; coreutils (stat/date) and
# grep back the health-file healthcheck; sqlite3 provides the online-backup API
# for consistent DB backups; tini gives correct PID 1 signal forwarding.
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates wget unzip libfontconfig1 coreutils grep sqlite3 tini \
	&& rm -rf /var/lib/apt/lists/*

RUN wget -q "${GODOT_URL}" -O /tmp/godot.zip \
	&& unzip -q /tmp/godot.zip -d /tmp/godot \
	&& mv "/tmp/godot/${GODOT_BINARY}" /usr/local/bin/godot \
	&& chmod +x /usr/local/bin/godot \
	&& rm -rf /tmp/godot /tmp/godot.zip \
	&& godot --version

WORKDIR /app
COPY . /app

# Bake the import cache so GDExtensions and resources resolve at runtime without
# writing res:// on first boot.
RUN godot --headless --path /app --import 2>&1 | tail -n 30 || true

COPY deploy/game-server/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY deploy/game-server/healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

# Non-root runtime user; owns the source tree (for any runtime reimport) and the
# writable data home where user:// (accounts.db, Canon) lives.
RUN useradd --system --uid 10001 --home-dir /data --create-home godot \
	&& chown -R godot:godot /app /data

USER godot
ENV HOME=/data \
	PROJECT0_SERVER_BIND_ADDRESS=0.0.0.0 \
	PROJECT0_SERVER_PORT=9999 \
	PROJECT0_ACCOUNTS_DB_PATH=accounts.db \
	PROJECT0_HEALTH_FILE=/data/health.json

EXPOSE 9999/udp

# Slice 067: liveness follows the runtime health file the server rewrites each
# tick (fresh + status "healthy"), so a frozen tick loop is caught even while the
# UDP socket stays bound.
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
	CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
