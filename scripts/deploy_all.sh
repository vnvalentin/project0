#!/usr/bin/env bash
# Deploys a committed Project0 revision to every service in deploy/services.json
# (Slice 104). Runs ON the deployment host — the self-hosted CI runner executes
# it locally, which is why no SSH or deploy credential is involved.
#
# Adding a service to CD is one entry in deploy/services.json; this script does
# not change.
#
# Usage:
#   scripts/deploy_all.sh --commit <sha> [--only a,b] [--dry-run] [--no-rollback]
#
# Safety model:
#   - The tree deployed is always `git archive <commit>`, never a working tree.
#   - The previous deploy root is moved aside to a timestamped backup first.
#   - Persistent data lives outside the deploy root (/var/lib/project0,
#     /var/backups/project0) and is never touched.
#   - Every service must pass its declared health check. On failure the previous
#     tree is restored and the affected units are restarted, unless
#     --no-rollback was given.
#   - Secrets are never generated, copied, or printed; units read them from
#     /etc/project0/*.env, which lives outside the deploy root.

set -euo pipefail

COMMIT=""
ONLY=""
DRY_RUN=false
ROLLBACK=true

while [[ $# -gt 0 ]]; do
	case "$1" in
		--commit) COMMIT="$2"; shift 2 ;;
		--only) ONLY="$2"; shift 2 ;;
		--dry-run) DRY_RUN=true; shift ;;
		--no-rollback) ROLLBACK=false; shift ;;
		*) echo "ERROR: unknown argument '$1'" >&2; exit 2 ;;
	esac
done

cd "$(dirname "${BASH_SOURCE[0]}")/.."
source_repo="$(pwd)"
registry="${source_repo}/deploy/services.json"
[[ -f "${registry}" ]] || { echo "ERROR: missing ${registry}" >&2; exit 1; }

[[ -n "${COMMIT}" ]] || COMMIT="$(git rev-parse HEAD)"
git cat-file -e "${COMMIT}^{commit}" 2>/dev/null || { echo "ERROR: '${COMMIT}' is not a commit" >&2; exit 1; }
COMMIT="$(git rev-parse "${COMMIT}")"

log() { printf '\n== %s\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

# Registry access goes through python3 stdlib json so the registry needs no
# third-party YAML parser on the host.
reg() { python3 -c "
import json,sys
r=json.load(open('${registry}'))
sys.stdout.write(str(eval(sys.argv[1], {'r': r})))
" "$1"; }

DEPLOY_ROOT="$(reg "r['deploy_root']")"
BACKUP_ROOT="$(reg "r['backup_root']")"

mapfile -t SERVICES < <(python3 -c "
import json
r=json.load(open('${registry}'))
only=set(filter(None, '${ONLY}'.split(',')))
for s in r['services']:
    if not only or s['name'] in only:
        print(s['name'])
")
[[ ${#SERVICES[@]} -gt 0 ]] || fail "no services selected"

svc() { python3 -c "
import json,sys
r=json.load(open('${registry}'))
s=[x for x in r['services'] if x['name']==sys.argv[1]][0]
print(eval(sys.argv[2], {'s': s}))
" "$1" "$2"; }

# `systemctl list-unit-files` exits nonzero for an absent unit, which under
# `set -o pipefail` would abort the whole run instead of reporting a skip.
unit_state() {
	systemctl list-unit-files "$1" --no-legend 2>/dev/null | awk '{print $2}' || true
}

unit_installed() { [[ -n "$(unit_state "$1")" ]]; }

log "Deploy plan"
echo "  commit      : ${COMMIT}"
echo "  deploy root : ${DEPLOY_ROOT}"
echo "  services    : ${SERVICES[*]}"
echo "  dry run     : ${DRY_RUN}"

# ---------------------------------------------------------------- health check
check_health() {
	local name="$1" kind url expect path max_age compose unit
	kind="$(svc "${name}" "s['health']['kind']")"
	case "${kind}" in
		systemd-active)
			unit="$(svc "${name}" "s['health']['unit']")"
			systemctl is-active --quiet "${unit}"
			;;
		health-file)
			path="$(svc "${name}" "s['health']['path']")"
			max_age="$(svc "${name}" "s['health']['max_age_seconds']")"
			[[ -f "${path}" ]] || return 1
			python3 -c "
import json,sys,time,os
p=sys.argv[1]; max_age=float(sys.argv[2])
age=time.time()-os.path.getmtime(p)
d=json.load(open(p))
status=str(d.get('status','')).lower()
sys.exit(0 if age<=max_age and status in ('healthy','ok') else 1)
" "${path}" "${max_age}"
			;;
		http)
			url="$(svc "${name}" "s['health']['url']")"
			expect="$(svc "${name}" "s['health']['expect_status']")"
			[[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${url}")" == "${expect}" ]]
			;;
		compose-running)
			compose="$(svc "${name}" "s['health']['compose_file']")"
			docker compose -f "${DEPLOY_ROOT}/${compose}" ps --status running --quiet | grep -q .
			;;
		*)
			fail "unknown health kind '${kind}' for ${name}"
			;;
	esac
}

await_health() {
	local name="$1" attempts="${2:-12}" i
	for ((i = 1; i <= attempts; i++)); do
		if check_health "${name}"; then
			echo "  health OK: ${name} (attempt ${i})"
			return 0
		fi
		sleep 5
	done
	return 1
}

# ------------------------------------------------------------------ dry run
if [[ "${DRY_RUN}" == true ]]; then
	log "Dry run: resolving registry and current health only; nothing is changed"
	for name in "${SERVICES[@]}"; do
		unit=""
		[[ "$(svc "${name}" "s['kind']")" == "systemd" ]] && unit="$(svc "${name}" "s['unit']")"
		installed="n/a"
		if [[ -n "${unit}" ]]; then
			installed="$(unit_state "${unit}")"
			[[ -n "${installed}" ]] || installed="NOT-INSTALLED"
		fi
		if check_health "${name}" 2>/dev/null; then health="healthy"; else health="unhealthy/absent"; fi
		printf '  %-14s required=%-5s unit=%-28s installed=%-13s health=%s\n' \
			"${name}" "$(svc "${name}" "s['required']")" "${unit:-–}" "${installed}" "${health}"
	done
	log "Dry run complete"
	exit 0
fi

# --------------------------------------------------------------- preflight
log "Preflight"
for name in "${SERVICES[@]}"; do
	if [[ "$(svc "${name}" "s['kind']")" == "systemd" ]]; then
		unit="$(svc "${name}" "s['unit']")"
		if ! unit_installed "${unit}"; then
			if [[ "$(svc "${name}" "s['required']")" == "True" ]]; then
				fail "required unit ${unit} is not installed on this host"
			fi
			echo "  skipping ${name}: unit ${unit} not installed"
		fi
	fi
done

stamp="$(date -u +%Y%m%d%H%M%S)"
backup="${BACKUP_ROOT}/$(basename "${DEPLOY_ROOT}").backup.${stamp}-$(git rev-parse --short "${COMMIT}")"
staging="$(mktemp -d)"
trap 'rm -rf "${staging}"' EXIT

log "Staging commit $(git rev-parse --short "${COMMIT}")"
git archive --format=tar "${COMMIT}" | tar -x -C "${staging}"
for name in "${SERVICES[@]}"; do
	check="$(svc "${name}" "s['source_check']")"
	[[ -f "${staging}/${check}" ]] || fail "staged tree is missing ${check} for ${name}"
done
echo "  staged tree validated for: ${SERVICES[*]}"

log "Backing up current deploy root to ${backup}"
[[ -d "${DEPLOY_ROOT}" ]] && mv "${DEPLOY_ROOT}" "${backup}"
mkdir -p "${DEPLOY_ROOT}"
cp -a "${staging}/." "${DEPLOY_ROOT}/"

restore_backup() {
	echo "ROLLBACK: restoring ${backup} to ${DEPLOY_ROOT}" >&2
	rm -rf "${DEPLOY_ROOT}"
	mv "${backup}" "${DEPLOY_ROOT}"
	for n in "${SERVICES[@]}"; do
		[[ "$(svc "${n}" "s['kind']")" == "systemd" ]] || continue
		u="$(svc "${n}" "s['unit']")"
		sudo -n systemctl restart "${u}" 2>/dev/null || true
	done
}

# Python services share a venv that lives inside the deploy root, so it is
# replaced along with the source and must be rebuilt before the units restart.
log "Synchronizing Python virtual environments"
declare -A venv_done=()
for name in "${SERVICES[@]}"; do
	venv="$(svc "${name}" "s.get('venv','')")"
	[[ -n "${venv}" ]] || continue
	requirements="$(svc "${name}" "s.get('requirements','')")"
	if [[ -z "${venv_done[${venv}]:-}" ]]; then
		[[ -d "${DEPLOY_ROOT}/${venv}" ]] || python3 -m venv "${DEPLOY_ROOT}/${venv}"
		venv_done[${venv}]=1
	fi
	"${DEPLOY_ROOT}/${venv}/bin/pip" -q install -r "${DEPLOY_ROOT}/${requirements}" \
		|| { [[ "${ROLLBACK}" == true ]] && restore_backup; fail "dependency install failed for ${name}"; }
	echo "  ${name}: ${requirements} installed into ${venv}"
done

log "Restarting services"
for name in "${SERVICES[@]}"; do
	kind="$(svc "${name}" "s['kind']")"
	if [[ "${kind}" == "systemd" ]]; then
		unit="$(svc "${name}" "s['unit']")"
		unit_installed "${unit}" || { echo "  skipped ${name}"; continue; }
		sudo -n systemctl restart "${unit}"
		echo "  restarted ${unit}"
	else
		compose="$(svc "${name}" "s['compose_file']")"
		[[ -f "${DEPLOY_ROOT}/${compose}" ]] || { echo "  skipped ${name}"; continue; }
		docker compose -f "${DEPLOY_ROOT}/${compose}" up -d --build
		echo "  composed ${compose}"
	fi
done

log "Verifying health"
failed=()
for name in "${SERVICES[@]}"; do
	if [[ "$(svc "${name}" "s['kind']")" == "systemd" ]]; then
		unit="$(svc "${name}" "s['unit']")"
		unit_installed "${unit}" || { echo "  skipped ${name}"; continue; }
	fi
	await_health "${name}" || failed+=("${name}")
done

if [[ ${#failed[@]} -gt 0 ]]; then
	echo "UNHEALTHY AFTER DEPLOY: ${failed[*]}" >&2
	if [[ "${ROLLBACK}" == true ]]; then
		restore_backup
		fail "deployment rolled back; previous tree restored from ${backup}"
	fi
	fail "deployment left unhealthy services and rollback was disabled; backup at ${backup}"
fi

log "Deployment complete"
echo "  commit  : ${COMMIT}"
echo "  services: ${SERVICES[*]}"
echo "  backup  : ${backup}"
