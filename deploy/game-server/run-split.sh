#!/usr/bin/env bash
# Slice 083: one-command launcher for the Project0 login-split deployment.
#
# Brings up the split topology defined by the base compose file plus the split
# overlay and the login-split profile: an accounts-authority login container and
# an accounts-disabled (assertion-only) game container that share one
# PROJECT0_ASSERTION_SECRET. The shared secret is the piece a bare `docker
# compose up` cannot manage safely — if the two processes do not share a
# non-empty secret they each fall back to an ephemeral per-boot key and the
# login->game handoff silently fails. This script fills that gap: it requires (or
# generates) a shared secret before starting both containers.
#
# Usage:
#   ./run-split.sh up      # start the split (generates a secret if unset)
#   ./run-split.sh down    # stop and remove the split
#
# Pin PROJECT0_ASSERTION_SECRET in your environment to keep issued sessions valid
# across restarts; otherwise each `up` generates a fresh ephemeral secret.
set -euo pipefail

cd "$(dirname "$0")"

COMPOSE=(docker compose -f docker-compose.yml -f docker-compose.split.yml --profile login-split)
GAME_CONTAINER="project0-game-server-candidate"
LOGIN_CONTAINER="project0-login-server-candidate"

_health() {
	docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null || echo none
}

case "${1:-up}" in
	up)
		if [ -z "${PROJECT0_ASSERTION_SECRET:-}" ]; then
			export PROJECT0_ASSERTION_SECRET="$(openssl rand -hex 32)"
			echo "[run-split] Generated an ephemeral shared assertion secret for this run."
			echo "[run-split] Pin PROJECT0_ASSERTION_SECRET to keep sessions valid across restarts."
		else
			echo "[run-split] Using PROJECT0_ASSERTION_SECRET from the environment."
		fi
		"${COMPOSE[@]}" up -d
		echo "[run-split] Split topology started (game assertion-only + login). Waiting for health..."
		for _ in $(seq 1 24); do
			sleep 5
			game="$(_health "$GAME_CONTAINER")"
			login="$(_health "$LOGIN_CONTAINER")"
			echo "[run-split] game=${game} login=${login}"
			if [ "$game" = healthy ] && [ "$login" = healthy ]; then
				echo "[run-split] Split topology healthy."
				exit 0
			fi
		done
		echo "[run-split] Timed out waiting for both containers to become healthy." >&2
		exit 1
		;;
	down)
		"${COMPOSE[@]}" down
		echo "[run-split] Split topology stopped."
		;;
	*)
		echo "usage: $0 [up|down]" >&2
		exit 2
		;;
esac
