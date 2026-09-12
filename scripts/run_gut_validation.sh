#!/usr/bin/env bash
set -u

GODOT_BIN="${GODOT_BIN:-godot}"
RESULT_DIR="${RESULT_DIR:-build/validation}"
JUNIT_FILE="${RESULT_DIR}/gut.xml"
LOG_FILE="${RESULT_DIR}/gut.log"
SUMMARY_FILE="${RESULT_DIR}/validation-summary.json"

mkdir -p "$RESULT_DIR"

set +e
"$GODOT_BIN" --headless \
  -s addons/gut/gut_cmdln.gd \
  -gjunit_xml_file="$JUNIT_FILE" \
  -gdisable_colors \
  -gexit 2>&1 | tee "$LOG_FILE"
exit_code=${PIPESTATUS[0]}
set -e

status="failed"
if [[ "$exit_code" -eq 0 ]]; then
  status="passed"
fi

cat > "$SUMMARY_FILE" <<EOF
{
  "runner": "GUT",
  "status": "$status",
  "exit_code": $exit_code,
  "timestamp_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "junit_xml": "$JUNIT_FILE",
  "log": "$LOG_FILE"
}
EOF

exit "$exit_code"
