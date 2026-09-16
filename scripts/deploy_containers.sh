#!/usr/bin/env bash
# Deploys the Project0 stack from published container images (Slice 106).
#
# Runs ON the deployment host; the self-hosted CI runner executes it locally,
# so there is no SSH hop and no deploy credential. This replaces the
# `git archive` model in scripts/deploy_all.sh, which depended on artifacts
# (.godot import cache, wgnetstack .so, host venv) that only ever existed on
# this one machine.
#
# Usage:
#   scripts/deploy_containers.sh --tag <image-tag> [--profiles a,b] [--dry-run]
#                                [--no-rollback]
#
# Safety model:
#   - Deploys an immutable image tag; rollback re-deploys the previous tag,
#     which is recorded before anything changes.
#   - Persistent data lives in host volumes under /var/lib/project0 and is
#     never touched by a deploy.
#   - Secrets stay in /etc/project0/*.env, outside the repo and the images.
#   - Every service must pass its health check or the previous tag is restored.

set -euo pipefail

TAG=""
PROFILES=""
DRY_RUN=false
ROLLBACK=true

while [[ $# -gt 0 ]]; do
	case "$1" in
		--tag) TAG="$2"; shift 2 ;;
		--profiles) PROFILES="$2"; shift 2 ;;
		--dry-run) DRY_RUN=true; shift ;;
		--no-rollback) ROLLBACK=false; shift ;;
		*) echo "ERROR: unknown argument '$1'" >&2; exit 2 ;;
	esac
done

cd "$(dirname "${BASH_SOURCE[0]}")/.."
compose_file="$(pwd)/deploy/compose.yml"
[[ -f "${compose_file}" ]] || { echo "ERROR: missing ${compose_file}" >&2; exit 1; }

[[ -n "${TAG}" ]] || TAG="main"
state_file="/var/lib/project0/deployed-tag"

log() { printf '\n== %s\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

compose_args=(-f "${compose_file}")
if [[ -n "${PROFILES}" ]]; then
	IFS=',' read -ra _profiles <<<"${PROFILES}"
	for p in "${_profiles[@]}"; do compose_args+=(--profile "${p}"); done
fi

previous_tag="$(cat "${state_file}" 2>/dev/null || echo "")"

log "Deploy plan"
echo "  compose file  : ${compose_file}"
echo "  image tag     : ${TAG}"
echo "  previous tag  : ${previous_tag:-<none recorded>}"
echo "  profiles      : ${PROFILES:-<default>}"
echo "  dry run       : ${DRY_RUN}"

services="$(PROJECT0_IMAGE_TAG="${TAG}" docker compose "${compose_args[@]}" config --services | tr '\n' ' ')"
echo "  services      : ${services}"

if [[ "${DRY_RUN}" == true ]]; then
	log "Dry run: resolving images and current state only; nothing is changed"
	PROJECT0_IMAGE_TAG="${TAG}" docker compose "${compose_args[@]}" config --images
	docker compose "${compose_args[@]}" ps 2>/dev/null || true
	log "Dry run complete"
	exit 0
fi

# Pulling before stopping anything keeps the current stack serving while the new
# images download, and fails the deploy before any downtime if a tag is missing.
# A tag push starts the image build and this deploy at the same time, so retry
# to absorb registry propagation rather than failing a legitimate release.
log "Pulling images for tag ${TAG}"
pull_attempts="${PULL_ATTEMPTS:-20}"
pulled=false
for ((attempt = 1; attempt <= pull_attempts; attempt++)); do
	if PROJECT0_IMAGE_TAG="${TAG}" docker compose "${compose_args[@]}" pull >/dev/null 2>&1; then
		echo "  pulled tag ${TAG} (attempt ${attempt})"
		pulled=true
		break
	fi
	echo "  tag ${TAG} not available yet (attempt ${attempt}/${pull_attempts})"
	sleep 15
done
if [[ "${pulled}" != true ]]; then
	# Surface the real error now that retries are exhausted.
	PROJECT0_IMAGE_TAG="${TAG}" docker compose "${compose_args[@]}" pull || true
	fail "image pull failed for tag '${TAG}'; nothing was changed"
fi

log "Starting stack"
PROJECT0_IMAGE_TAG="${TAG}" docker compose "${compose_args[@]}" up -d --remove-orphans \
	|| fail "compose up failed for tag '${TAG}'"

# Health is what proves a deploy. Containers without a declared healthcheck are
# proven by staying up, since a crash-looping container is not "running".
await_health() {
	local attempts=24 i name state health unhealthy
	for ((i = 1; i <= attempts; i++)); do
		unhealthy=""
		for name in ${services}; do
			local cid
			cid="$(docker compose "${compose_args[@]}" ps -q "${name}" 2>/dev/null || true)"
			[[ -n "${cid}" ]] || { unhealthy="${unhealthy} ${name}(absent)"; continue; }
			state="$(docker inspect -f '{{.State.Status}}' "${cid}")"
			health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${cid}")"
			if [[ "${state}" != "running" ]]; then
				unhealthy="${unhealthy} ${name}(${state})"
			elif [[ "${health}" != "none" && "${health}" != "healthy" ]]; then
				unhealthy="${unhealthy} ${name}(${health})"
			fi
		done
		if [[ -z "${unhealthy}" ]]; then
			echo "  all services healthy (attempt ${i})"
			return 0
		fi
		sleep 5
	done
	echo "  still not healthy:${unhealthy}" >&2
	return 1
}

log "Waiting for health"
if ! await_health; then
	docker compose "${compose_args[@]}" ps
	if [[ "${ROLLBACK}" == true && -n "${previous_tag}" ]]; then
		log "ROLLBACK: redeploying previous tag ${previous_tag}"
		PROJECT0_IMAGE_TAG="${previous_tag}" docker compose "${compose_args[@]}" up -d --remove-orphans || true
		fail "deploy of '${TAG}' failed health; rolled back to '${previous_tag}'"
	fi
	fail "deploy of '${TAG}' failed health and no previous tag was recorded to roll back to"
fi

# Recorded only after health passes, so the rollback target is always a tag that
# was observed healthy on this host. /var/lib/project0 is root-owned, so write
# via sudo directly rather than relying on a failed redirect as control flow.
sudo -n mkdir -p "$(dirname "${state_file}")"
printf '%s\n' "${TAG}" | sudo -n tee "${state_file}" >/dev/null

log "Deployed tag ${TAG}"
docker compose "${compose_args[@]}" ps
