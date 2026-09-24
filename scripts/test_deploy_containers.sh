#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

fixture_repo="$fixture/repo"
mkdir -p "$fixture/bin" "$fixture/apps/project0" "$fixture/var/lib/project0" \
	"$fixture_repo/scripts" "$fixture_repo/deploy"
cp "$repo_root/scripts/deploy_containers.sh" "$fixture_repo/scripts/"
cp "$repo_root/deploy/compose.yml" "$fixture_repo/deploy/"
cp "$repo_root/deploy/smoke-checks.json" "$fixture_repo/deploy/"
deploy_script="$fixture_repo/scripts/deploy_containers.sh"
source_compose="$fixture_repo/deploy/compose.yml"
command_log="$fixture/commands.log"
docker_state="$fixture/docker-state"

cat > "$fixture/bin/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'sudo %s\n' "$*" >> "$COMMAND_LOG"
[[ "${1:-}" == "-n" ]] && shift
exec "$@"
EOF

cat > "$fixture/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'docker %s\n' "$*" >> "$COMMAND_LOG"

if [[ "$*" == *"config --services"* ]]; then
	printf '%s\n' game-server login-server enrollment operator nakama nakama-db
elif [[ "$*" == *"config --images"* ]]; then
	printf '%s\n' ghcr.io/vnvalentin/project0-game-server:sha-test
elif [[ "$*" == *" pull "* && "${PROJECT0_IMAGE_TAG:-}" == "sha-missing" ]]; then
	exit 1
elif [[ "$*" == *"ps -q game-server"* ]]; then
	printf '%s\n' game-server-container
elif [[ "$*" == *" up -d "* ]]; then
	printf '%s\n' "${PROJECT0_IMAGE_TAG:-unknown}" > "$DOCKER_STATE"
elif [[ "${1:-}" == "inspect" && "$*" == *"State.Status"* ]]; then
	printf '%s\n' running
elif [[ "${1:-}" == "inspect" && "$*" == *"State.Health"* ]]; then
	if [[ "$(cat "$DOCKER_STATE" 2>/dev/null || true)" == "sha-bad" ]]; then
		printf '%s\n' unhealthy
	else
		printf '%s\n' none
	fi
fi
EOF

chmod +x "$fixture/bin/sudo" "$fixture/bin/docker"
export COMMAND_LOG="$command_log"
export DOCKER_STATE="$docker_state"

missing_service_output="$({
	PATH="$fixture/bin:$PATH" \
	PROJECT0_DEPLOY_ROOT="$fixture/apps/project0" \
	PROJECT0_STATE_DIR="$fixture/var/lib/project0" \
	bash "$deploy_script" --tag sha-test
} 2>&1 || true)"
grep -q 'at least one --service is required' <<<"$missing_service_output"

PATH="$fixture/bin:$PATH" \
PROJECT0_DEPLOY_ROOT="$fixture/apps/project0" \
PROJECT0_STATE_DIR="$fixture/var/lib/project0" \
PULL_ATTEMPTS=1 \
HEALTH_ATTEMPTS=1 \
HEALTH_SLEEP_SECONDS=0 \
bash "$deploy_script" \
	--tag sha-test \
	--service game-server >/dev/null

artifact="$fixture/apps/project0/deploy/compose.yml"
cmp "$source_compose" "$artifact"
grep -Eq "sudo -n mv .+ ${artifact}$" "$command_log"
grep -Fq "docker compose -p project0 -f ${artifact} pull game-server" "$command_log"
grep -Fq "docker compose -p project0 -f ${artifact} up -d game-server" "$command_log"

if grep -E 'docker compose .* (pull|up -d) .*\b(login-server|enrollment|operator|nakama|nakama-db)\b' "$command_log"; then
	echo 'unrelated service appeared in a targeted deploy' >&2
	exit 1
fi

prior_compose="$fixture/prior-compose.yml"
cp "$artifact" "$prior_compose"
printf '\n# rollback candidate\n' >> "$source_compose"

rollback_output="$({
	PATH="$fixture/bin:$PATH" \
	PROJECT0_DEPLOY_ROOT="$fixture/apps/project0" \
	PROJECT0_STATE_DIR="$fixture/var/lib/project0" \
	PULL_ATTEMPTS=1 \
	HEALTH_ATTEMPTS=1 \
	HEALTH_SLEEP_SECONDS=0 \
	bash "$deploy_script" --tag sha-bad --service game-server
} 2>&1 || true)"

grep -q "rolled back to 'sha-test'" <<<"$rollback_output"
cmp "$prior_compose" "$artifact"
[[ "$(cat "$docker_state")" == "sha-test" ]]

printf '\n# pull failure candidate\n' >> "$source_compose"
pull_failure_output="$({
	PATH="$fixture/bin:$PATH" \
	PROJECT0_DEPLOY_ROOT="$fixture/apps/project0" \
	PROJECT0_STATE_DIR="$fixture/var/lib/project0" \
	PULL_ATTEMPTS=1 \
	bash "$deploy_script" --tag sha-missing --service game-server
} 2>&1 || true)"

grep -q "restored previous Compose artifact" <<<"$pull_failure_output"
cmp "$prior_compose" "$artifact"
[[ "$(cat "$docker_state")" == "sha-test" ]]

printf 'deploy containers: durable artifact, targeted service, and recovery verified\n'