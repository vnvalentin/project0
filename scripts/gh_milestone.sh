#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' \
    'Usage:' \
    '  scripts/gh_milestone.sh list [open|closed|all]' \
    '  scripts/gh_milestone.sh create TITLE [DESCRIPTION] [DUE_ON] [STATE]' \
    '  scripts/gh_milestone.sh edit NUMBER TITLE [DESCRIPTION] [DUE_ON] [STATE]' \
    '  scripts/gh_milestone.sh close NUMBER' \
    '  scripts/gh_milestone.sh reopen NUMBER' \
    '  scripts/gh_milestone.sh delete NUMBER'
}

require_number() {
  case "$1" in
    ''|0|*[!0-9]*)
      printf 'milestone number must be a positive integer: %s\n' "$1" >&2
      exit 2
      ;;
  esac
}

require_state() {
  case "$1" in
    open|closed) ;;
    *) printf 'state must be open or closed: %s\n' "$1" >&2; exit 2 ;;
  esac
}

api() {
  gh api "$@"
}

command_name="${1:-}"
case "$command_name" in
  list)
    state="${2:-open}"
    case "$state" in
      open|closed|all) ;;
      *) printf 'state must be open, closed, or all: %s\n' "$state" >&2; exit 2 ;;
    esac
    api --method GET "repos/{owner}/{repo}/milestones?state=${state}&per_page=100"
    ;;
  create)
    [[ $# -ge 2 && $# -le 5 ]] || { usage >&2; exit 2; }
    require_state "${5:-open}"
    fields=(-f "title=$2" -f "state=${5:-open}")
    [[ -z "${3:-}" ]] || fields+=(-f "description=$3")
    [[ -z "${4:-}" ]] || fields+=(-f "due_on=$4")
    api --method POST "repos/{owner}/{repo}/milestones" "${fields[@]}"
    ;;
  edit)
    [[ $# -ge 3 && $# -le 6 ]] || { usage >&2; exit 2; }
    require_number "$2"
    [[ -z "${6:-}" ]] || require_state "$6"
    fields=(-f "title=$3")
    [[ -z "${4:-}" ]] || fields+=(-f "description=$4")
    [[ -z "${5:-}" ]] || fields+=(-f "due_on=$5")
    [[ -z "${6:-}" ]] || fields+=(-f "state=$6")
    api --method PATCH "repos/{owner}/{repo}/milestones/$2" "${fields[@]}"
    ;;
  close|reopen)
    [[ $# -eq 2 ]] || { usage >&2; exit 2; }
    require_number "$2"
    state=open
    [[ "$command_name" == close ]] && state=closed
    api --method PATCH "repos/{owner}/{repo}/milestones/$2" -f "state=$state"
    ;;
  delete)
    [[ $# -eq 2 ]] || { usage >&2; exit 2; }
    require_number "$2"
    api --method DELETE "repos/{owner}/{repo}/milestones/$2"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
