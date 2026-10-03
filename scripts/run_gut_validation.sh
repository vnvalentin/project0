#!/usr/bin/env bash
set -u

GODOT_BIN="${GODOT_BIN:-godot}"
GUT_TIMEOUT_SECONDS="${GUT_TIMEOUT_SECONDS:-900}"
RESULT_DIR="${RESULT_DIR:-build/validation}"
JUNIT_FILE="${RESULT_DIR}/gut.xml"
LOG_FILE="${RESULT_DIR}/gut.log"
IMPORT_LOG="${RESULT_DIR}/import.log"
SUMMARY_FILE="${RESULT_DIR}/validation-summary.json"
DASHBOARD_RESULTS_DIR="${DASHBOARD_RESULTS_DIR:-}"
if [[ -z "$DASHBOARD_RESULTS_DIR" && -d "/apps/project0/dashboard/repo" ]]; then
  DASHBOARD_RESULTS_DIR="/apps/project0/dashboard/repo/build/validation"
fi

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    echo "VALIDATION GATE ERROR: GUT validates the Linux-only Godot server and must not run on Windows." >&2
    echo "Use: scripts/run_windows_launcher_validation.ps1" >&2
    exit 2
    ;;
esac

# Bind M4 evidence to this checkout. Source-only container artifacts obtain the
# verified host revision through the explicit environment instead of Git.
if [[ ${M4_SOURCE_REVISION+x} && ! "$M4_SOURCE_REVISION" =~ ^[0-9a-f]{40}$ ]]; then
  echo "VALIDATION GATE ERROR: M4_SOURCE_REVISION must be a full 40-hex Git revision." >&2
  exit 2
fi
checkout_revision="$(git rev-parse --verify HEAD 2>/dev/null || true)"
if [[ "$checkout_revision" =~ ^[0-9a-f]{40}$ ]]; then
  if [[ ${M4_SOURCE_REVISION+x} && "$M4_SOURCE_REVISION" != "$checkout_revision" ]]; then
    echo "VALIDATION GATE ERROR: supplied M4 source revision differs from checkout HEAD." >&2
    exit 2
  fi
  export M4_SOURCE_REVISION="$checkout_revision"
elif [[ ! ${M4_SOURCE_REVISION+x} ]]; then
  echo "VALIDATION GATE ERROR: source artifacts without Git require M4_SOURCE_REVISION." >&2
  exit 2
else
  export M4_SOURCE_REVISION
fi

source_root="$PWD"
if [[ -n "$DASHBOARD_RESULTS_DIR" && "$DASHBOARD_RESULTS_DIR" != /* ]]; then
  DASHBOARD_RESULTS_DIR="$source_root/$DASHBOARD_RESULTS_DIR"
fi
mkdir -p "$RESULT_DIR"
RESULT_DIR="$(cd "$RESULT_DIR" && pwd)"
JUNIT_FILE="${RESULT_DIR}/gut.xml"
LOG_FILE="${RESULT_DIR}/gut.log"
IMPORT_LOG="${RESULT_DIR}/import.log"
SUMMARY_FILE="${RESULT_DIR}/validation-summary.json"
PREPARATION_REPORT="${RESULT_DIR}/preparation-summary.json"

record_bootstrap_failure() {
  python3 - "$SUMMARY_FILE" <<'PYREPORT'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    "runner":"GUT", "status":"failed", "stage":"bootstrap", "exit_code":2,
    "scripts_ran":0, "gut_execution":"NOT_OBSERVED",
},indent=2)+"\n")
PYREPORT
}

if ! command -v timeout >/dev/null 2>&1; then
  echo "VALIDATION GATE ERROR: GNU timeout is required to bound the GUT process." | tee -a "$LOG_FILE"
  exit 1
fi

# Godot loads GDExtension classes from this registry before its first editor
# scan discovers extension declarations. The helper seeds the reviewed extension
# only in its owned copy; the original checkout remains untouched.
# Existing unknown registry state is rejected rather than silently replaced.
extension_declaration="addons/godot-sqlite/gdsqlite.gdextension"
extension_registry=".godot/extension_list.cfg"
if [[ ! -f "$extension_declaration" || -L "$extension_declaration" || -L .godot || -L "$extension_registry" ]]; then
  echo "VALIDATION GATE ERROR: server extension bootstrap requires ordinary owned source/cache paths." >&2
  record_bootstrap_failure
  exit 2
fi
if [[ -e "$extension_registry" ]]; then
  if [[ ! -f "$extension_registry" ]] || ! cmp -s "$extension_registry" <(printf '%s\n' "res://$extension_declaration"); then
    echo "VALIDATION GATE ERROR: extension registry differs from the reviewed server declaration." >&2
    record_bootstrap_failure
    exit 2
  fi
fi

# Reimport/compile from a clean cache before running so a stale GDScript class
# cache cannot silently drop a test script from the run and still report green
# (DT-007). A skipped script must never be mistaken for a passing suite.
source_root="$PWD"
prepared_parent="$(mktemp -d "${TMPDIR:-/tmp}/project0-gut-prepared.XXXXXX")" || { record_bootstrap_failure; exit 2; }
prepared_root="$prepared_parent/project"
publish_dashboard_results() {
if [[ -n "$DASHBOARD_RESULTS_DIR" ]]; then
  if mkdir -p "$DASHBOARD_RESULTS_DIR" \
    && cp "$JUNIT_FILE" "$DASHBOARD_RESULTS_DIR/gut.xml" \
    && cp "$SUMMARY_FILE" "$DASHBOARD_RESULTS_DIR/validation-summary.json"; then
    echo "Published dashboard test results to $DASHBOARD_RESULTS_DIR"
  else
    echo "WARNING: unable to publish dashboard test results to $DASHBOARD_RESULTS_DIR" >&2
  fi
fi

}
record_cleanup_failure() {
  python3 - "$SUMMARY_FILE" "$prepared_root" "$1" <<'PYCLEANUP'
import json, sys
from pathlib import Path
path, root, reason = sys.argv[1:]
try:
    result = json.loads(Path(path).read_text())
    if not isinstance(result, dict):
        result = {}
except (OSError, ValueError):
    result = {}
result.update(status="failed", stage="cleanup", exit_code=1,
              cleanup_failure=reason, retained_prepared_root=root)
Path(path).write_text(json.dumps(result, indent=2)+"\n")
PYCLEANUP
  publish_dashboard_results
}
cleanup_prepared_source() {
  runner_exit=$?
  trap - EXIT
  if ! python3 - "$PREPARATION_REPORT" "$prepared_root" "$M4_SOURCE_REVISION" <<'PYCUSTODY'
import hashlib, json, stat, sys
from pathlib import Path
try:
    report = Path(sys.argv[1])
    if report.is_symlink() or not report.is_file():
        sys.exit(1)
    result = json.loads(report.read_text())
    root = Path(sys.argv[2])
    qualified = (isinstance(result, dict) and result.get("configuration_custody_lost") is False
                 and result.get("prepared_root") == sys.argv[2]
                 and result.get("source_revision") == sys.argv[3]
                 and isinstance(result.get("prepared_root_created"), bool)
                 and (result["prepared_root_created"] is False
                      or (result.get("configuration_restored") is True
                          and result.get("source_custody_qualified") is True)))
    if qualified and result["prepared_root_created"]:
        config = root / "project.godot"
        cache = root / ".godot"
        registry = cache / "extension_list.cfg"
        override = root / "override.cfg"
        qualified = (not root.is_symlink() and not cache.is_symlink()
                     and not config.is_symlink() and stat.S_ISREG(config.lstat().st_mode)
                     and hashlib.sha256(config.read_bytes()).hexdigest() == result.get("configuration_original_sha256")
                     and not registry.is_symlink() and stat.S_ISREG(registry.lstat().st_mode)
                     and registry.read_bytes() == b"res://addons/godot-sqlite/gdsqlite.gdextension\n"
                     and not override.exists() and not override.is_symlink())
except (OSError, ValueError):
    sys.exit(1)
sys.exit(0 if qualified else 1)
PYCUSTODY
  then
    record_cleanup_failure "configuration_custody_unqualified"
    echo "VALIDATION GATE ERROR: staged source retained because configuration custody is unqualified." >&2
    exit 1
  fi
  # Existing tests own res://logs/experiments/*.json. Retain only those generated
  # artifacts in the established host destination, without replacing prior files.
  if ! python3 - "$prepared_root" "$source_root" "$RESULT_DIR" <<'PYARTIFACTS'
import hashlib, json, os, stat, sys
from pathlib import Path
stage, source, results = map(Path, sys.argv[1:])
origin = stage / "logs/experiments"
try:
    manifest = []
    if origin.exists() or origin.is_symlink():
        if (stage / "logs").is_symlink() or origin.is_symlink() or not origin.is_dir():
            raise ValueError("artifact_root_unqualified")
        paths = []
        for directory, directories, files in os.walk(origin, followlinks=False):
            parent = Path(directory)
            for name in directories:
                if (parent / name).is_symlink():
                    raise ValueError("artifact_directory_unqualified")
            for name in files:
                path = parent / name
                if not stat.S_ISREG(path.lstat().st_mode) or path.suffix != ".json":
                    raise ValueError("artifact_file_unqualified")
                paths.append(path)
        destination = source / "logs/experiments"
        for root in (source / "logs", destination):
            if root.is_symlink() or (root.exists() and not root.is_dir()):
                raise ValueError("artifact_destination_unqualified")
        # Preflight every destination before writing any generated evidence.
        for incoming in paths:
            relative = incoming.relative_to(origin)
            outgoing = destination / relative
            for parent in [outgoing, *outgoing.parents]:
                if parent == source:
                    break
                if parent.is_symlink():
                    raise ValueError("artifact_destination_unqualified")
            if outgoing.exists():
                raise ValueError("artifact_destination_collision")
        for incoming in paths:
            outgoing = destination / incoming.relative_to(origin)
            outgoing.parent.mkdir(parents=True, exist_ok=True)
            payload = incoming.read_bytes()
            with outgoing.open("xb") as stream:
                stream.write(payload)
            if outgoing.read_bytes() != payload:
                raise ValueError("artifact_readback_failed")
            manifest.append({"path": str(outgoing), "sha256": hashlib.sha256(payload).hexdigest()})
    (results / "experiment-artifacts.json").write_text(json.dumps({"status":"retained", "files":manifest},indent=2)+"\n")
except (OSError, ValueError):
    sys.exit(1)
PYARTIFACTS
  then
    record_cleanup_failure "experiment_artifacts_unqualified"
    echo "VALIDATION GATE ERROR: staged experiment artifacts retained for recovery." >&2
    exit 1
  fi
  if ! rm -rf -- "$prepared_parent" || [[ -e "$prepared_parent" ]]; then
    record_cleanup_failure "prepared_source_teardown_failed"
    exit 1
  fi
  publish_dashboard_results
  exit "$runner_exit"
}
trap cleanup_prepared_source EXIT

GODOT_BIN="$(command -v "$GODOT_BIN")" || { record_bootstrap_failure; exit 2; }
if [[ "$GODOT_BIN" != /* ]]; then GODOT_BIN="$source_root/$GODOT_BIN"; fi
set +e
python3 "$source_root/scripts/prepare_godot_project.py" \
  --source-root "$source_root" --prepared-root "$prepared_root" \
  --godot "$GODOT_BIN" --source-revision "$M4_SOURCE_REVISION" \
  --timeout-seconds "$GUT_TIMEOUT_SECONDS" --report "$PREPARATION_REPORT" >"$IMPORT_LOG" 2>&1
import_exit_code=$?
set -e
import_script_error_observed=false
import_log_scan_failed=false
if grep -Eq 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script' "$IMPORT_LOG"; then
  import_script_error_observed=true
else
  scan_exit=$?
  if [[ "$scan_exit" -gt 1 ]]; then
    import_log_scan_failed=true
  fi
fi
if [[ "$import_exit_code" -ne 0 || "$import_script_error_observed" == true || "$import_log_scan_failed" == true ]]; then
  python3 - "$SUMMARY_FILE" "$IMPORT_LOG" "$import_exit_code" "$import_script_error_observed" "$import_log_scan_failed" "$PREPARATION_REPORT" "$M4_SOURCE_REVISION" "$prepared_root" <<'PYREPORT'
import json,sys
from pathlib import Path
summary,log,code,marker,scan_failed,preparation,revision,prepared=sys.argv[1:]
code=int(code)
timed_out = True if code in (124,137) else "NOT_OBSERVED"
report_valid = False
try:
    evidence = Path(preparation)
    if evidence.is_symlink() or not evidence.is_file():
        raise ValueError("unavailable_report")
    report = json.loads(evidence.read_text())
    if (not isinstance(report, dict) or report.get("schema_version") != 1
            or report.get("source_revision") != revision or report.get("prepared_root") != prepared):
        raise ValueError("unqualified_report")
    flags = []
    for phase in ("bootstrap", "qualification"):
        observed = report.get(phase)
        if isinstance(observed, dict):
            if not isinstance(observed.get("timed_out"), bool):
                raise ValueError("unqualified_phase")
            flags.append(observed["timed_out"])
        elif observed != "NOT_OBSERVED":
            raise ValueError("unqualified_phase")
    report_valid = True
    if flags:
        timed_out = timed_out is True or any(flags)
except (OSError, ValueError):
    pass
Path(summary).write_text(json.dumps({
    "runner":"GUT", "status":"failed", "stage":"import", "exit_code":1,
    "import_exit_code":code, "import_script_error_observed":marker=="true",
    "import_log_scan_failed":scan_failed=="true",
    "timed_out":timed_out, "preparation_report_valid":report_valid,
    "preparation_report":preparation, "scripts_ran":0, "gut_execution":"NOT_OBSERVED",
    "import_log":log,
},indent=2)+"\n")
PYREPORT
  echo "VALIDATION GATE ERROR: import preparation failed; selected tests were not run." >&2
  exit 1
fi

cd "$prepared_root" || { record_bootstrap_failure; exit 2; }
# GUT runtime state stays inside the same owned lifecycle as its source copy.
gut_runtime_home="$prepared_parent/runtime-home"
gut_runtime_data="$prepared_parent/runtime-data"
gut_runtime_config="$prepared_parent/runtime-config"
gut_runtime_cache="$prepared_parent/runtime-cache"
mkdir -p "$gut_runtime_home" "$gut_runtime_data" "$gut_runtime_config" "$gut_runtime_cache"

set +e
env HOME="$gut_runtime_home" XDG_DATA_HOME="$gut_runtime_data" \
  XDG_CONFIG_HOME="$gut_runtime_config" XDG_CACHE_HOME="$gut_runtime_cache" \
  timeout --kill-after=15s "${GUT_TIMEOUT_SECONDS}s" "$GODOT_BIN" --headless \
  -s addons/gut/gut_cmdln.gd \
  -gjunit_xml_file="$JUNIT_FILE" \
  -gdisable_colors \
  -gexit 2>&1 | tee "$LOG_FILE"
exit_code=${PIPESTATUS[0]}
set -e

timed_out=false
if [[ "$exit_code" -eq 124 || "$exit_code" -eq 137 ]]; then
  timed_out=true
  echo "VALIDATION GATE ERROR: GUT exceeded ${GUT_TIMEOUT_SECONDS}s and was terminated." | tee -a "$LOG_FILE"
fi

# Gate hardening (DT-007): a suite is only trustworthy if EVERY test script
# actually ran. GUT exits 0 even when a script fails to parse (it silently skips
# it), so verify each on-disk test_*.gd produced a testsuite in the JUnit report
# and fail closed otherwise — a skipped script must never read as green.
scripts_expected=0
scripts_ran=0
missing_scripts=""
for test_file in tests/unit/test_*.gd tests/integration/test_*.gd; do
  [[ -e "$test_file" ]] || continue
  scripts_expected=$((scripts_expected + 1))
  if grep -q "testsuite name=\"$test_file\"" "$JUNIT_FILE" 2>/dev/null; then
    scripts_ran=$((scripts_ran + 1))
  else
    missing_scripts="$missing_scripts $test_file"
  fi
done

if [[ "$scripts_expected" -eq 0 ]]; then
  echo "VALIDATION GATE ERROR: no test_*.gd scripts found under tests/ — wrong working directory or broken checkout." | tee -a "$LOG_FILE"
  exit_code=1
elif [[ -n "$missing_scripts" ]]; then
  echo "VALIDATION GATE ERROR: only $scripts_ran/$scripts_expected test scripts ran; these were silently skipped (parse error or stale cache):$missing_scripts" | tee -a "$LOG_FILE"
  exit_code=1
fi

gut_script_error_observed=false
gut_log_scan_failed=false
if grep -Eq 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script' "$LOG_FILE"; then
  gut_script_error_observed=true
  exit_code=1
  echo "VALIDATION GATE ERROR: GUT emitted a script error despite its reported test result." | tee -a "$LOG_FILE"
else
  scan_exit=$?
  if [[ "$scan_exit" -gt 1 ]]; then
    gut_log_scan_failed=true
    exit_code=1
    echo "VALIDATION GATE ERROR: GUT script-error evidence could not be read." >&2
  fi
fi

status="failed"
if [[ "$exit_code" -eq 0 ]]; then
  status="passed"
fi

python3 - "$SUMMARY_FILE" "$status" "$exit_code" "$timed_out" "$GUT_TIMEOUT_SECONDS" \
  "$scripts_expected" "$scripts_ran" "$gut_script_error_observed" "$gut_log_scan_failed" \
  "$PREPARATION_REPORT" "$JUNIT_FILE" "$LOG_FILE" <<'PYSUMMARY'
import datetime, json, sys
from pathlib import Path
path, status, code, timed, timeout, expected, ran, marker, scan, preparation, junit, log = sys.argv[1:]
Path(path).write_text(json.dumps({
    "runner":"GUT", "status":status, "exit_code":int(code), "timed_out":timed=="true",
    "timeout_seconds":int(timeout), "scripts_expected":int(expected), "scripts_ran":int(ran),
    "gut_script_error_observed":marker=="true", "gut_log_scan_failed":scan=="true",
    "preparation_report":preparation, "timestamp_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "junit_xml":junit, "log":log,
},indent=2)+"\n")
PYSUMMARY


exit "$exit_code"
