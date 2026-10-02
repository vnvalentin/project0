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

mkdir -p "$RESULT_DIR"

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
# scan discovers extension declarations. Seed only the reviewed server extension
# so a fresh validation checkout can compile the same typed SQLite consumers.
# Existing unknown registry state is rejected rather than silently replaced.
extension_declaration="addons/godot-sqlite/gdsqlite.gdextension"
extension_registry=".godot/extension_list.cfg"
if [[ ! -f "$extension_declaration" || -L "$extension_declaration" || -L .godot || -L "$extension_registry" ]]; then
  echo "VALIDATION GATE ERROR: server extension bootstrap requires ordinary owned source/cache paths." >&2
  record_bootstrap_failure
  exit 2
fi
mkdir -p .godot || { record_bootstrap_failure; exit 2; }
if [[ -e "$extension_registry" ]]; then
  if [[ ! -f "$extension_registry" ]] || ! cmp -s "$extension_registry" <(printf '%s\n' "res://$extension_declaration"); then
    echo "VALIDATION GATE ERROR: extension registry differs from the reviewed server declaration." >&2
    record_bootstrap_failure
    exit 2
  fi
elif ! (set -C; printf '%s\n' "res://$extension_declaration" > "$extension_registry"); then
  echo "VALIDATION GATE ERROR: extension registry preparation failed." >&2
  record_bootstrap_failure
  exit 2
fi

# Reimport/compile from a clean cache before running so a stale GDScript class
# cache cannot silently drop a test script from the run and still report green
# (DT-007). A skipped script must never be mistaken for a passing suite.
set +e
timeout --kill-after=15s "${GUT_TIMEOUT_SECONDS}s" "$GODOT_BIN" --headless --import >"$IMPORT_LOG" 2>&1
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
  python3 - "$SUMMARY_FILE" "$IMPORT_LOG" "$import_exit_code" "$import_script_error_observed" "$import_log_scan_failed" <<'PYREPORT'
import json,sys
from pathlib import Path
summary,log,code,marker,scan_failed=sys.argv[1:]
code=int(code)
Path(summary).write_text(json.dumps({
    "runner":"GUT", "status":"failed", "stage":"import", "exit_code":1,
    "import_exit_code":code, "import_script_error_observed":marker=="true",
    "import_log_scan_failed":scan_failed=="true",
    "timed_out":code in (124,137), "scripts_ran":0, "gut_execution":"NOT_OBSERVED",
    "import_log":log,
},indent=2)+"\n")
PYREPORT
  echo "VALIDATION GATE ERROR: import preparation failed; selected tests were not run." >&2
  exit 1
fi

set +e
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

cat > "$SUMMARY_FILE" <<EOF
{
  "runner": "GUT",
  "status": "$status",
  "exit_code": $exit_code,
  "timed_out": $timed_out,
  "timeout_seconds": $GUT_TIMEOUT_SECONDS,
  "scripts_expected": $scripts_expected,
  "scripts_ran": $scripts_ran,
  "gut_script_error_observed": $gut_script_error_observed,
  "gut_log_scan_failed": $gut_log_scan_failed,
  "timestamp_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "junit_xml": "$JUNIT_FILE",
  "log": "$LOG_FILE"
}
EOF

if [[ -n "$DASHBOARD_RESULTS_DIR" ]]; then
  if mkdir -p "$DASHBOARD_RESULTS_DIR" \
    && cp "$JUNIT_FILE" "$DASHBOARD_RESULTS_DIR/gut.xml" \
    && cp "$SUMMARY_FILE" "$DASHBOARD_RESULTS_DIR/validation-summary.json"; then
    echo "Published dashboard test results to $DASHBOARD_RESULTS_DIR"
  else
    echo "WARNING: unable to publish dashboard test results to $DASHBOARD_RESULTS_DIR" >&2
  fi
fi

exit "$exit_code"
