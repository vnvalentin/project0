#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
test_id="probe-$$"
for unsafe in --privileged "--network host" "--cap-add SYS_ADMIN"; do
	read -r -a arguments <<< "$unsafe"
	if bash scripts/run_hosted_gut_container.sh --probe "${arguments[@]}" >/dev/null 2>&1; then
		echo "unsafe container option was accepted: $unsafe" >&2
		exit 1
	fi
done

if PROJECT0_HOSTED_GUT_TEST_ID="$test_id" PROJECT0_HOSTED_GUT_PROBE_FAIL=1 \
		bash scripts/run_hosted_gut_container.sh --probe; then
	echo "induced container failure unexpectedly passed" >&2
	exit 1
fi
grep -q '"passed": false' build/validation/hosted-container-tests.json
[[ -z "$(docker ps -aq --filter "label=project0.hosted-gut=$test_id")" ]]

PROJECT0_HOSTED_GUT_TEST_ID="$test_id" bash scripts/run_hosted_gut_container.sh --probe
grep -q '"passed": true' build/validation/hosted-container-tests.json
[[ -z "$(docker ps -aq --filter "label=project0.hosted-gut=$test_id")" ]]