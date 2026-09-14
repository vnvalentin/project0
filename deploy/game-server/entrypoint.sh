#!/bin/sh
# Entry point for the containerized authoritative Project0 server. Resolves the
# bind address and port from the environment (NetworkConfig also reads these),
# then execs Godot headless so tini (PID 1) forwards SIGTERM for a graceful
# docker stop. Mirrors scripts/project0-server.service's invocation.
set -eu

BIND="${PROJECT0_SERVER_BIND_ADDRESS:-0.0.0.0}"
PORT="${PROJECT0_SERVER_PORT:-9999}"

mkdir -p "${HOME}"
echo "[entrypoint] Project0 authoritative server starting (bind=${BIND} port=${PORT} home=${HOME})"

exec godot --headless --path /app -s server/server_main.gd \
	-- --server-bind-address="${BIND}" --server-port="${PORT}"
