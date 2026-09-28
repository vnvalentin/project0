#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
test_id="probe-$$"
unsafe_statuses=()
for unsafe in --privileged "--network host" "--cap-add SYS_ADMIN"; do
	read -r -a arguments <<< "$unsafe"
	set +e
	bash scripts/run_hosted_gut_container.sh --probe "${arguments[@]}" >/dev/null 2>&1
	unsafe_status=$?
	set -e
	if [[ "$unsafe_status" -ne 2 ]]; then
		echo "unsafe container option was accepted: $unsafe" >&2
		exit 1
	fi
	unsafe_statuses+=("$unsafe_status")
done

set +e
PROJECT0_HOSTED_GUT_TEST_ID="$test_id" PROJECT0_HOSTED_GUT_PROBE_FAIL=1 \
	bash scripts/run_hosted_gut_container.sh --probe
induced_status=$?
set -e
if [[ "$induced_status" -ne 23 ]]; then
	echo "induced container failure unexpectedly passed" >&2
	exit 1
fi
grep -q '"passed": false' build/validation/hosted-container-tests.json
cp build/validation/hosted-container-tests.json build/validation/hosted-container-failure.json
failure_survivors="$(docker ps -aq --filter "label=project0.hosted-gut=$test_id" | wc -l)"
[[ "$failure_survivors" -eq 0 ]]

PROJECT0_HOSTED_GUT_TEST_ID="$test_id" bash scripts/run_hosted_gut_container.sh --probe
grep -q '"passed": true' build/validation/hosted-container-tests.json
success_survivors="$(docker ps -aq --filter "label=project0.hosted-gut=$test_id" | wc -l)"
[[ "$success_survivors" -eq 0 ]]

cat > build/validation/hosted-container-tests.json <<EOF
{
	"passed": true,
	"tests": 5,
	"failures": 0,
	"errors": 0,
	"skipped": 0,
	"cases": [
		{"name": "reject_privileged", "passed": true, "exit_code": ${unsafe_statuses[0]}},
		{"name": "reject_network_host", "passed": true, "exit_code": ${unsafe_statuses[1]}},
		{"name": "reject_cap_add", "passed": true, "exit_code": ${unsafe_statuses[2]}},
		{"name": "induced_failure_cleanup", "passed": true, "exit_code": $induced_status, "surviving_containers": $failure_survivors},
		{"name": "host_sealer_success", "passed": true, "exit_code": 0, "surviving_containers": $success_survivors}
	]
}
EOF