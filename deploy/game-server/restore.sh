#!/bin/sh
# Guarded restore of a SQLite backup into the game server's host data dir. Stops
# the container, replaces the live DB via a throwaway container (so the restored
# file keeps the non-root uid the server runs as), clears stale WAL/SHM, checks
# integrity, and restarts. Run on the Linux host.
# Usage: restore.sh <backup-file-on-host> [data-dir]
set -eu

BACKUP="${1:?usage: restore.sh <backup-file> [data-dir]}"
DATA_DIR="${2:-/var/lib/project0/game}"
IMAGE="${PROJECT0_GAME_IMAGE:-project0-game-server:candidate}"
COMPOSE="$(dirname "$0")/docker-compose.yml"
REL="/data/.local/share/godot/app_userdata/Project0/accounts.db"

[ -f "${BACKUP}" ] || { echo "[restore] backup not found: ${BACKUP}" >&2; exit 1; }

echo "[restore] stopping container"
docker compose -f "${COMPOSE}" stop || true

echo "[restore] restoring ${BACKUP} into ${DATA_DIR}"
# --entrypoint sh is required: the image ENTRYPOINT starts the server, so a
# one-shot maintenance container must override it to run cp/sqlite3 instead.
docker run --rm --entrypoint sh \
	-v "${DATA_DIR}:/data" \
	-v "$(cd "$(dirname "${BACKUP}")" && pwd):/src:ro" \
	"${IMAGE}" \
	-c "mkdir -p \"$(dirname ${REL})\" \
		&& cp \"/src/$(basename "${BACKUP}")\" \"${REL}\" \
		&& rm -f \"${REL}-wal\" \"${REL}-shm\" \
		&& sqlite3 \"${REL}\" 'PRAGMA integrity_check;'"

echo "[restore] restarting container"
docker compose -f "${COMPOSE}" up -d
echo "[restore] done"
