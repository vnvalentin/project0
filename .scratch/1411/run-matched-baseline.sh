#!/usr/bin/env bash
set -euo pipefail

baseline_ref="${1:-}"
image_id="${2:-}"
if [[ ! "$baseline_ref" =~ ^[0-9a-f]{40}$ || ! "$image_id" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  printf 'usage: %s <40-hex-baseline-revision> sha256:<64 lowercase hex>\n' "$0" >&2
  exit 2
fi

exec 9>/tmp/project0-m4-01a0fcfa-validation.lock
flock -n 9

candidate_root="$(git rev-parse --show-toplevel)"
candidate_revision="$(git rev-parse --verify HEAD)"
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  printf 'VALIDATION BLOCKED: candidate source is dirty\n' >&2
  exit 2
fi
baseline_revision="$(git rev-parse --verify "$baseline_ref^{commit}")"
[[ "$baseline_revision" == "$baseline_ref" ]]

run_id="$(date -u +%Y%m%dT%H%M%S%N)"
evidence_root="${PROJECT0_VALIDATION_RESULTS_ROOT:-$candidate_root/build/validation}"
evidence_dir="$evidence_root/m4-1411-matched-baseline-$run_id"
mkdir -p "$evidence_dir"
worktree="$(dirname "$candidate_root")/project0-1411-baseline-$run_id"

cleanup() {
  result=$?
  if git -C "$candidate_root" worktree list --porcelain | grep -Fqx "worktree $worktree"; then
    git -C "$candidate_root" worktree remove --force "$worktree" || result=1
  fi
  exit "$result"
}
trap cleanup EXIT

git -C "$candidate_root" worktree add --detach "$worktree" "$baseline_revision" >/dev/null
login_pid="$(docker inspect --format '{{.State.Pid}}' project0-login-server)"
game_pid="$(docker inspect --format '{{.State.Pid}}' project0-game-server)"
[[ "$login_pid" =~ ^[1-9][0-9]*$ && "$game_pid" =~ ^[1-9][0-9]*$ ]]
login_cgroup="$(cat "/proc/$login_pid/cgroup")"
game_cgroup="$(cat "/proc/$game_pid/cgroup")"

monitor_args=(
  --root "$worktree"
  --expected-revision "$baseline_revision"
  --timeout-seconds 900
  --require-root
  --run-as-sudo-caller
  --allowed-cgroup "$login_cgroup"
  --allowed-cgroup "$game_cgroup"
)
sudo_args=(--preserve-env=PATH,LANG)
python="/data/code/project0/.venv-enrollment/bin/python"
set +e
sudo -n "${sudo_args[@]}" "$python" "$worktree/scripts/run_validation_monitor.py" \
  "${monitor_args[@]}" \
  --report "$evidence_dir/review-validation.json" \
  -- python3 scripts/run_m4_baseline.py --server-image "$image_id" \
  --supported-load --crossing-span 10 --checkpoint-attribution \
  > "$evidence_dir/monitor-command.log" 2>&1
monitor_status=$?
set -e

python3 - "$candidate_revision" "$baseline_revision" "$image_id" "$evidence_dir" "$worktree" "$monitor_status" <<'PY'
import hashlib
import json
import shutil
import stat
import sys
from pathlib import Path

candidate, baseline, image_id, evidence, worktree, monitor_status = sys.argv[1:]
evidence, worktree = Path(evidence), Path(worktree)
monitor_status = int(monitor_status)
root = worktree / "logs/experiments"
reports = sorted(root.glob("exp_m4_1_baseline_*.json"), key=lambda path: path.stat().st_mtime_ns)
if len(reports) != 1:
    raise SystemExit("matched_baseline_report_missing_or_ambiguous")
source_report = reports[0]
measurement = json.loads(source_report.read_text(encoding="utf-8"))
if (measurement.get("source") != baseline or measurement.get("source_dirty") is not False
        or measurement.get("supported_load") is not True
        or measurement.get("checkpoint_attribution") is not True
        or measurement.get("requested_ticks") != 1000
        or measurement.get("container", {}).get("image_id") != image_id):
    raise SystemExit("matched_baseline_identity_or_profile_mismatch")
if measurement.get("cleanup", {}).get("verified") is not True:
    raise SystemExit("matched_baseline_cleanup_unverified")
if measurement.get("competing_engines_before") or measurement.get("competing_engines_during"):
    raise SystemExit("matched_baseline_competing_engine_observed")
if measurement.get("checkpoint_summary", {}).get("qualified") is not True:
    raise SystemExit("matched_baseline_checkpoint_attribution_unqualified")

retained = []
def copy_artifact(source):
    if source.is_symlink() or not stat.S_ISREG(source.lstat().st_mode):
        raise ValueError("matched_baseline_artifact_not_regular")
    target = evidence / "experiments" / source.relative_to(root)
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() or target.is_symlink():
        raise ValueError("matched_baseline_artifact_collision")
    data = source.read_bytes()
    target.write_bytes(data)
    digest = hashlib.sha256(data).hexdigest()
    if hashlib.sha256(target.read_bytes()).hexdigest() != digest:
        raise ValueError("matched_baseline_artifact_readback_failed")
    retained.append({"path": str(target), "sha256": digest})

for path in sorted(root.rglob("*")):
    if path.is_symlink():
        raise SystemExit("matched_baseline_artifact_symlink")
    if path.is_file():
        if path.suffix not in (".json", ".log", ".tar"):
            raise SystemExit("matched_baseline_artifact_type_unexpected")
        copy_artifact(path)

monitor = json.loads((evidence / "review-validation.json").read_text(encoding="utf-8"))
monitor_integrity = (
    monitor.get("source_revision") == baseline
    and monitor.get("source_unchanged") is True
    and monitor.get("forced_recovery") is False
    and monitor.get("errors") == []
    and monitor.get("cleanup", {}).get("owned_processes_stopped") is True
)
summary = {
    "schema_version": 1,
    "candidate_revision": candidate,
    "baseline_revision": baseline,
    "image_id": image_id,
    "monitor_command_exit_code": monitor_status,
    "monitor_integrity_qualified": monitor_integrity,
    "measurement_report": str(source_report),
    "measurement_passed": measurement.get("passed") is True,
    "ticks_observed": len(measurement.get("observation", {}).get("samples", [])),
    "failed_checks": measurement.get("evaluation", {}).get("failed_checks", []),
    "evaluation": measurement.get("evaluation"),
    "checkpoint_summary": measurement.get("checkpoint_summary"),
    "m4_cleanup_verified": measurement.get("cleanup", {}).get("verified") is True,
    "retained_artifacts": retained,
}
summary["evidence_complete"] = bool(
    monitor_integrity and summary["m4_cleanup_verified"] and summary["ticks_observed"] == 1000
)
with (evidence / "measurement-summary.json").open("x", encoding="utf-8") as stream:
    stream.write(json.dumps(summary, indent=2, sort_keys=True) + "\n")
print(json.dumps({"evidence_complete": summary["evidence_complete"],
                  "measurement_passed": summary["measurement_passed"],
                  "ticks_observed": summary["ticks_observed"],
                  "failed_checks": summary["failed_checks"],
                  "candidate_revision": candidate,
                  "baseline_revision": baseline,
                  "evidence_dir": str(evidence)}, sort_keys=True))
if not summary["evidence_complete"]:
    raise SystemExit("matched_baseline_evidence_incomplete")
PY