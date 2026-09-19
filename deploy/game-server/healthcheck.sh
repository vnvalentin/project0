#!/bin/sh
# Slice 067: container liveness for the authoritative Project0 server. The server
# rewrites a small JSON health file (via HealthReporter) every ~0.5s. Healthy
# requires the file to exist, be fresh (written within the staleness window), and
# report status "healthy" — a truer signal than "a UDP socket is bound", because
# a frozen tick loop stops refreshing the file while the socket stays open.
# Exit 0 = healthy, non-zero = unhealthy. See docs/slices/067-*.
set -eu

FILE="${PROJECT0_HEALTH_FILE:-/data/health.json}"
STALE_SECONDS="${PROJECT0_HEALTH_STALE_SECONDS:-20}"

[ -f "$FILE" ] || exit 1

now="$(date +%s)"
mtime="$(stat -c %Y "$FILE" 2>/dev/null || echo 0)"
[ "$(( now - mtime ))" -le "$STALE_SECONDS" ] || exit 1

grep -Eq '"status"[[:space:]]*:[[:space:]]*"healthy"' "$FILE" || exit 1
