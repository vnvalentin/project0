#!/bin/sh
# Consistent online backup of the running containerized game server's SQLite
# database into the host backup directory (mounted at /backup). Uses the SQLite
# .backup API, which is safe against a live WAL database (no torn file copy).
# Run on the Linux host. Usage: backup.sh [container-name]
set -eu

CONTAINER="${1:-project0-game-server-candidate}"
DB_PATH="${PROJECT0_GAME_DB:-/data/.local/share/godot/app_userdata/Project0/accounts.db}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
DEST="/backup/project0-game-${TS}.sqlite3"

echo "[backup] ${CONTAINER}:${DB_PATH} -> ${DEST} (host: /var/backups/project0)"
docker exec "${CONTAINER}" sh -c "sqlite3 '${DB_PATH}' \".backup '${DEST}'\""
echo "[backup] integrity:"
docker exec "${CONTAINER}" sh -c "sqlite3 '${DEST}' 'PRAGMA integrity_check;'"
echo "[backup] done: ${DEST}"
