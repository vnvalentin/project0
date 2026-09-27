#!/bin/bash
set -euo pipefail

if [[ "${GITHUB_REPOSITORY:-}" != "vnvalentin/project0" || "${GITHUB_REF:-}" != "refs/heads/fix/1265-trusted-admission" || "${GITHUB_SHA:-}" != "${PROJECT0_PROBE_SHA:-unset}" ]]; then
  exit 0
fi

printf 'PROJECT0_ADMISSION_PROBE job=%s pid=%s parent=%s\n' "${GITHUB_JOB:-unknown}" "$$" "$PPID"
if [[ "${GITHUB_JOB:-}" == "denied" ]]; then
  printf 'PROJECT0_ADMISSION_DENIED\n'
  exit 66
fi
printf 'PROJECT0_ADMISSION_ALLOWED\n'