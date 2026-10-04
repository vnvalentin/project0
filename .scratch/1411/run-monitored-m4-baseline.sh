#!/usr/bin/env bash
set -euo pipefail

image_id="${1:-}"
profile="${2:-supported-load}"
if [[ ! "$image_id" =~ ^sha256:[0-9a-f]{64}$ || ( "$profile" != "supported-load" && "$profile" != "isolation" ) ]]; then
    printf 'usage: %s sha256:<64 lowercase hex> [supported-load|isolation]\n' "$0" >&2
  exit 2
fi

exec 9>/tmp/project0-m4-01a0fcfa-validation.lock
flock -n 9

repo_root="$(git rev-parse --show-toplevel)"
revision="$(git rev-parse --verify HEAD)"
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  printf 'VALIDATION BLOCKED: candidate source is dirty\n' >&2
  exit 2
fi

run_id="$(date -u +%Y%m%dT%H%M%S%N)"
evidence_root="${PROJECT0_VALIDATION_RESULTS_ROOT:-$repo_root/build/validation}"
evidence_dir="$evidence_root/m4-1411-load-$run_id"
mkdir -p "$evidence_dir"

login_pid="$(docker inspect --format '{{.State.Pid}}' project0-login-server)"
game_pid="$(docker inspect --format '{{.State.Pid}}' project0-game-server)"
[[ "$login_pid" =~ ^[1-9][0-9]*$ && "$game_pid" =~ ^[1-9][0-9]*$ ]]
login_cgroup="$(cat "/proc/$login_pid/cgroup")"
game_cgroup="$(cat "/proc/$game_pid/cgroup")"

monitor_args=(
  --root "$repo_root"
  --expected-revision "$revision"
  --timeout-seconds 900
  --require-root
  --run-as-sudo-caller
  --allowed-cgroup "$login_cgroup"
  --allowed-cgroup "$game_cgroup"
  --preserve-env PROJECT0_VALIDATION_RESULTS_ROOT
)
sudo_args=(--preserve-env=PATH,LANG,PROJECT0_VALIDATION_RESULTS_ROOT)
python="/data/code/project0/.venv-enrollment/bin/python"
started_ns="$(date +%s%N)"
m4_args=(python3 scripts/run_m4_baseline.py --server-image "$image_id" --crossing-span 10)
if [[ "$profile" == "supported-load" ]]; then
    m4_args+=(--supported-load --checkpoint-attribution)
fi

set +e
sudo -n "${sudo_args[@]}" "$python" scripts/run_validation_monitor.py \
  "${monitor_args[@]}" \
  --report "$evidence_dir/review-validation.json" \
    -- "${m4_args[@]}" \
  > "$evidence_dir/monitor-command.log" 2>&1
monitor_status=$?
set -e

python3 - "$repo_root" "$evidence_dir" "$revision" "$image_id" "$started_ns" "$monitor_status" "$profile" <<'PY'
import hashlib
import json
import shutil
import stat
import sys
from pathlib import Path

repo, evidence, revision, image_id, started_ns, monitor_status, profile = sys.argv[1:]
repo, evidence = Path(repo), Path(evidence)
started_ns, monitor_status = int(started_ns), int(monitor_status)
experiment_root = repo / "logs/experiments"
reports = sorted((path for path in experiment_root.glob("exp_m4_1_baseline_*.json")
                  if path.stat().st_mtime_ns >= started_ns),
                 key=lambda path: path.stat().st_mtime_ns)
if len(reports) != 1:
    raise SystemExit("m4_report_missing_or_ambiguous")
measurement_path = reports[0]
measurement = json.loads(measurement_path.read_text(encoding="utf-8"))
supported_load = profile == "supported-load"
if (measurement.get("source") != revision or measurement.get("source_dirty") is not False
    or measurement.get("supported_load") is not supported_load
    or measurement.get("checkpoint_attribution") is not supported_load
        or measurement.get("requested_ticks") != 1000
        or measurement.get("container", {}).get("image_id") != image_id):
    raise SystemExit("m4_source_or_profile_mismatch")
if measurement.get("cleanup", {}).get("verified") is not True:
    raise SystemExit("m4_cleanup_unverified")
if measurement.get("competing_engines_before") or measurement.get("competing_engines_during"):
    raise SystemExit("m4_competing_engine_observed")
if supported_load and measurement.get("checkpoint_summary", {}).get("qualified") is not True:
    raise SystemExit("m4_checkpoint_attribution_unqualified")

artifacts = []
def retain(source):
    if source.is_symlink() or not stat.S_ISREG(source.lstat().st_mode):
        raise ValueError("experiment_artifact_not_regular")
    relative = source.relative_to(experiment_root)
    destination = evidence / "experiments" / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() or destination.is_symlink():
        raise ValueError("experiment_artifact_collision")
    payload = source.read_bytes()
    destination.write_bytes(payload)
    digest = hashlib.sha256(payload).hexdigest()
    if hashlib.sha256(destination.read_bytes()).hexdigest() != digest:
        raise ValueError("experiment_artifact_readback_failed")
    artifacts.append({"path": str(destination), "sha256": digest})

retain(measurement_path)
failure_path = measurement_path.with_name(
    measurement_path.name.replace("exp_m4_1_baseline_", "exp_m4_1_FAIL_trace_"))
if failure_path.is_file():
    retain(failure_path)
folder = repo / str(measurement.get("artifacts", ""))
if not folder.is_dir() or folder.is_symlink():
    raise SystemExit("m4_artifact_folder_missing")
for path in sorted(folder.rglob("*")):
    if path.is_symlink():
        raise SystemExit("m4_artifact_symlink")
    if path.is_file():
        if path.suffix not in (".json", ".log", ".tar"):
            raise SystemExit("m4_artifact_type_unexpected")
        retain(path)

monitor_path = evidence / "review-validation.json"
monitor = json.loads(monitor_path.read_text(encoding="utf-8"))
monitor_integrity = (
    monitor.get("source_revision") == revision
    and monitor.get("source_unchanged") is True
    and monitor.get("forced_recovery") is False
    and monitor.get("errors") == []
    and monitor.get("cleanup", {}).get("owned_processes_stopped") is True
)
samples = measurement.get("observation", {}).get("samples", [])
checks = measurement.get("evaluation", {}).get("checks", {})
if profile == "isolation" and (
        checks.get("isolation_observed") is not True
        or checks.get("worker_activity_observed") is not True):
    raise SystemExit("m4_isolation_or_worker_evidence_unqualified")
summary = {
    "schema_version": 1,
    "source_revision": revision,
    "image_id": image_id,
    "profile": profile,
    "monitor_command_exit_code": monitor_status,
    "monitor_integrity_qualified": monitor_integrity,
    "measurement_report": str(measurement_path),
    "measurement_report_sha256": hashlib.sha256(measurement_path.read_bytes()).hexdigest(),
    "measurement_passed": measurement.get("passed") is True,
    "ticks_observed": len(samples),
    "failed_checks": measurement.get("evaluation", {}).get("failed_checks", []),
    "checkpoint_attribution": measurement.get("checkpoint_summary") if supported_load else None,
    "isolation_checks": {name: checks.get(name) for name in (
        "isolation_observed", "worker_activity_observed", "structural_nonblocking_verified",
        "lock_wait_observed")},
    "m4_cleanup_verified": measurement.get("cleanup", {}).get("verified") is True,
    "retained_artifacts": artifacts,
}
summary["evidence_complete"] = bool(
    monitor_integrity and summary["m4_cleanup_verified"] and len(samples) == 1000
    and checks.get("complete_tick_samples") is True
    and checks.get("finite_durations") is True
    and checks.get("full_workload_each_tick") is True
    and checks.get("crossings_at_least_two_per_second") is True
    and (checks.get("checkpoint_child_evidence_qualified") is True if supported_load else
         checks.get("isolation_observed") is True and checks.get("worker_activity_observed") is True)
)
with (evidence / "measurement-summary.json").open("x", encoding="utf-8") as stream:
    stream.write(json.dumps(summary, indent=2, sort_keys=True) + "\n")
print(json.dumps({"evidence_complete": summary["evidence_complete"],
                  "measurement_passed": summary["measurement_passed"],
                  "ticks_observed": summary["ticks_observed"],
                  "failed_checks": summary["failed_checks"],
                  "evidence_dir": str(evidence)}, sort_keys=True))
if not summary["evidence_complete"]:
    raise SystemExit("m4_evidence_incomplete")
PY