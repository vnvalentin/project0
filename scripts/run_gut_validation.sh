#!/usr/bin/env bash
set -u

GODOT_BIN="${GODOT_BIN:-godot}"
GUT_TIMEOUT_SECONDS="${GUT_TIMEOUT_SECONDS:-900}"
RESULT_DIR="${RESULT_DIR:-build/validation}"
JUNIT_FILE="${RESULT_DIR}/gut.xml"
LOG_FILE="${RESULT_DIR}/gut.log"
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

mkdir -p "$RESULT_DIR"

if ! command -v timeout >/dev/null 2>&1; then
  echo "VALIDATION GATE ERROR: GNU timeout is required to bound the GUT process." | tee -a "$LOG_FILE"
  exit 1
fi

# Reimport/compile from a clean cache before running so a stale GDScript class
# cache cannot silently drop a test script from the run and still report green
# (DT-007). A skipped script must never be mistaken for a passing suite.
timeout --kill-after=15s "${GUT_TIMEOUT_SECONDS}s" "$GODOT_BIN" --headless --import >/dev/null 2>&1 || true

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
