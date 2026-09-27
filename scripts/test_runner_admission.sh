#!/bin/bash
set -euo pipefail

if [[ "${GITHUB_REPOSITORY:-}" != "vnvalentin/project0" || "${GITHUB_REF:-}" != "refs/heads/fix/1265-trusted-admission" || "${GITHUB_SHA:-}" != "${PROJECT0_PROBE_SHA:-unset}" ]]; then
  exit 0
fi

printf 'PROJECT0_ADMISSION_PROBE job=%s pid=%s parent=%s\n' "${GITHUB_JOB:-unknown}" "$$" "$PPID"
if [[ "${GITHUB_JOB:-}" == "denied" ]]; then
  printf 'PROJECT0_ADMISSION_DENIED\n'
  worker_executable=$(/usr/bin/readlink -f "/proc/$PPID/exe")
  expected_executable=$(/usr/bin/readlink -f /data/actions-runner/bin/Runner.Worker)
  if [[ "$worker_executable" != "$expected_executable" || -z "${PROJECT0_PROBE_AUDIT:-}" ]]; then
    printf 'PROJECT0_ADMISSION_PARENT_UNVERIFIED\n'
    exit 79
  fi
  printf '{"decision":"deny","run_id":"%s","sha":"%s","worker_pid":%s,"worker_executable":"%s"}\n' "$GITHUB_RUN_ID" "$GITHUB_SHA" "$PPID" "$worker_executable" > "$PROJECT0_PROBE_AUDIT"
  /usr/bin/kill -KILL "$PPID"
  exit 66
fi
printf 'PROJECT0_ADMISSION_ALLOWED\n'