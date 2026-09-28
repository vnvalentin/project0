#!/bin/bash
set -u

worker_pid=$PPID
worker_executable=$(/usr/bin/readlink -f "/proc/$worker_pid/exe")
expected_executable=$(/usr/bin/readlink -f /data/actions-runner/bin/Runner.Worker)
if [[ -z "$worker_executable" || "$worker_executable" != "$expected_executable" ]]; then
  printf 'Admission launcher requires the pinned Runner.Worker parent.\n' >&2
  exit 78
fi

decision=$(/usr/bin/timeout --kill-after=2s 20s /usr/bin/python3 -I -S /etc/project0-ci/gate/ci_runner_admission.py --policy /etc/project0-ci/admission.json)
status=$?
printf '%s\n' "$decision"
/usr/bin/logger -t project0-ci-admission -p authpriv.notice -- "$decision"
if [[ "$status" == 0 ]]; then
  exit 0
fi

/usr/bin/logger -t project0-ci-admission -p authpriv.warning -- "deny run=${GITHUB_RUN_ID:-unknown} attempt=${GITHUB_RUN_ATTEMPT:-unknown} job=${GITHUB_JOB:-unknown} sha=${GITHUB_SHA:-unknown} worker=$worker_pid status=$status"
/usr/bin/kill -KILL "$worker_pid"
exit 66