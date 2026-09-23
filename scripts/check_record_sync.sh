#!/usr/bin/env bash
# Record-sync JKK gate. Fails when the delivery records disagree, so calibration
# drift is caught mechanically instead of relying on discipline. Run before every
# record commit (and ideally from a pre-commit hook).
#
# Checks (all against the working tree, i.e. what you are about to commit):
#   1. Dangling feature anchors  - every FEATURE-LIST.md#<id> link resolves to a
#      real "### <ID>:" section.
#   2. Feature well-formedness   - every feature heading has a recognized Status.
#   3. Slice registry coverage   - every docs/slices/NNN-*.md is listed in the
#      registry; no duplicate slice numbers.
#   4. Next-free pointer sanity  - registry "Next free slice" exceeds every known
#      slice number.
#   5. Slice-doc feature link     - each slice doc names an existing feature (warn).
#   6. GitHub Issue traceability  - every slice doc names a GitHub Issue.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

FEATURE=docs/FEATURE-LIST.md
TRACKER=docs/PROJECT-TRACKER.md
REGISTRY=docs/slices/SLICE-REGISTRY.md
SLICE_DIR=docs/slices

errors=0
warns=0
err()  { printf 'FAIL  %s\n' "$1" >&2; errors=$((errors + 1)); }
warn() { printf 'WARN  %s\n' "$1" >&2; warns=$((warns + 1)); }

# Structured tracker authority/parity gate. The Markdown file remains a frozen
# readable archive, but it must continue to import into the dashboard schema.
if ! python dashboard/tracker.py --validate .; then
	err "structured tracker schema is out of parity with docs/PROJECT-TRACKER.md"
fi

for f in "$FEATURE" "$TRACKER" "$REGISTRY"; do
	[ -f "$f" ] || err "missing record file: $f"
done
if [ "$errors" -gt 0 ]; then
	printf '\nrecord-sync: %d error(s)\n' "$errors" >&2
	exit 1
fi

# Feature IDs that actually have a heading in FEATURE-LIST.
feature_ids="$(grep -oE '^### (F|IP|P)-[0-9]+' "$FEATURE" | sed 's/^### //' | sort -u)"
has_feature() { grep -qxF "$1" <<<"$feature_ids"; }

# 1) Dangling feature anchors.
while IFS= read -r ref; do
	[ -n "$ref" ] || continue
	id="$(sed -E 's/.*#(f|ip|p)-([0-9]+).*/\U\1-\2/' <<<"$ref")"
	has_feature "$id" || err "dangling anchor '$ref' -> no '### $id:' section in $FEATURE"
done < <(grep -ohE 'FEATURE-LIST\.md#(f|ip|p)-[0-9]+' "$TRACKER" | sort -u)

# 2) Every feature heading has a recognized Status.
while IFS= read -r id; do
	[ -n "$id" ] || continue
	status="$(awk -v hdr="### $id:" '
		index($0, hdr) == 1 { inb = 1; next }
		inb && /^### / { exit }
		inb && /^- Status:/ { print; exit }
	' "$FEATURE")"
	if [ -z "$status" ]; then
		err "$id has no '- Status:' line"
	elif ! grep -qE 'Planned|Ready|In Progress|Implemented' <<<"$status"; then
		err "$id has unrecognized status:${status#*Status:}"
	fi
done <<<"$feature_ids"

# 3) Slice registry coverage + duplicate slice numbers.
# The registry tracks the contended range onward (001-026 are linear history);
# reserved-block rows like "100-199" are ranges, not allocations, so only count
# table rows whose first cell is a single number ("| 040 |").
shopt -s nullglob
mapfile -t reg_nums < <(grep -oE '^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$REGISTRY" | grep -oE '[0-9]+')
floor=9999
for n in "${reg_nums[@]}"; do
	v="$((10#$n))"
	[ "$v" -lt "$floor" ] && floor="$v"
done
[ "${#reg_nums[@]}" -eq 0 ] && floor=0

declare -A seen_doc
max_interactive=0
for doc in "$SLICE_DIR"/[0-9][0-9][0-9]-*.md; do
	pad="$(basename "$doc" | grep -oE '^[0-9]+')"
	num="$((10#$pad))"
	if [ -n "${seen_doc[$num]:-}" ]; then
		err "duplicate slice number $pad: ${seen_doc[$num]} and $doc"
	fi
	seen_doc[$num]="$doc"
	[ "$num" -lt 100 ] && [ "$num" -gt "$max_interactive" ] && max_interactive="$num"
	if [ "$num" -ge "$floor" ]; then
		grep -qE "^\|[[:space:]]*$pad[[:space:]]*\|" "$REGISTRY" ||
			err "slice $pad ($doc) at/after registry floor $floor but missing from $REGISTRY"
	fi
done

# 4) "Next free slice" must exceed the max interactive-block (001-099) slice.
for n in "${reg_nums[@]}"; do
	v="$((10#$n))"
	[ "$v" -lt 100 ] && [ "$v" -gt "$max_interactive" ] && max_interactive="$v"
done
next_free="$(grep -oE 'Next free slice:[^0-9]*[0-9]+' "$REGISTRY" | grep -oE '[0-9]+' | head -1)"
if [ -n "$next_free" ] && [ "$((10#$next_free))" -le "$max_interactive" ]; then
	err "registry 'Next free slice: $next_free' is not greater than max interactive slice $max_interactive"
fi

# 5) Each slice doc should name an existing feature (warn only).
declare -A frozen_feature_link_exceptions=(
	[docs/slices/002-client-connects-to-server.md]=1
	[docs/slices/003-lan-client-connection.md]=1
	[docs/slices/009-provisional-sector-generation.md]=1
	[docs/slices/010-core-mechanics-architecture.md]=1
	[docs/slices/038-shared-sqlite-persistence-foundation.md]=1
	[docs/slices/041-dt-006-remaining-smoke-test-gut-migration.md]=1
)
for doc in "${!frozen_feature_link_exceptions[@]}"; do
	[ -f "$doc" ] || err "frozen feature-link exception no longer exists: $doc"
done
for doc in "$SLICE_DIR"/[0-9][0-9][0-9]-*.md; do
	[ -n "${frozen_feature_link_exceptions[$doc]:-}" ] && continue
	ok=0
	while IFS= read -r id; do
		[ -n "$id" ] && has_feature "$id" && ok=1
	done < <(grep -oE '(F|IP|P)-[0-9]+' "$doc" | sort -u)
	[ "$ok" -eq 1 ] || warn "$doc names no feature present in $FEATURE"
done

# 6) Every slice doc must carry a GitHub Issue reference.
for doc in "$SLICE_DIR"/[0-9][0-9][0-9]-*.md; do
	pad="$(basename "$doc" | grep -oE '^[0-9]+')"
	if ! grep -qiE '^GitHub issue:[[:space:]]*(#[0-9]+|https://github\.com/[^/]+/[^/]+/issues/[0-9]+)' "$doc"; then
		err "slice $pad ($doc) missing GitHub issue traceability; add 'GitHub issue: #N' or an issue URL"
	fi
done

printf '\nrecord-sync: %d error(s), %d warning(s)\n' "$errors" "$warns" >&2
[ "$errors" -eq 0 ] || exit 1
exit 0
