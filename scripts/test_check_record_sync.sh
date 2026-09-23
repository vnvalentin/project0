#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/scripts" "$fixture/docs" "$fixture/dashboard"
cp -a "$repo_root/docs/." "$fixture/docs/"
cp "$repo_root/scripts/check_record_sync.sh" "$fixture/scripts/"
cp "$repo_root/dashboard/tracker.py" "$repo_root/dashboard/tracker_schema.json" "$fixture/dashboard/"

baseline_output="$(cd "$fixture" && bash scripts/check_record_sync.sh 2>&1)"
grep -q 'record-sync: 0 error(s), 0 warning(s)' <<<"$baseline_output"

cat > "$fixture/docs/slices/200-record-sync-regression.md" <<'EOF'
# Slice 200: Record sync regression fixture

GitHub issue: #999999
EOF
printf '| 200 | Record sync regression fixture | test |\n' >> "$fixture/docs/slices/SLICE-REGISTRY.md"

invalid_output="$(cd "$fixture" && bash scripts/check_record_sync.sh 2>&1)"
grep -q 'WARN  docs/slices/200-record-sync-regression.md names no feature present' <<<"$invalid_output"
grep -q 'record-sync: 0 error(s), 1 warning(s)' <<<"$invalid_output"

printf 'record-sync regression: baseline clean; invalid current record warns\n'
