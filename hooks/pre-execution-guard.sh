#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Reads the tool call as JSON on stdin.
# Exit 0 = allow, exit 2 = block (stderr is shown to the model). Never prompts.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATTERNS_FILE="${ROOT}/rules/destructive-patterns.json"
INCIDENT_LOG="${ROOT}/incidents/log.jsonl"

fail() {
  echo "agent-safety-guardrails: $1" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || fail "jq est requis (brew install jq)"
[[ -f "$PATTERNS_FILE" ]] || fail "fichier de motifs introuvable: $PATTERNS_FILE"

input="$(cat)"
jq -e . >/dev/null 2>&1 <<<"$input" || fail "entrée JSON invalide, appel bloqué par précaution"

cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"
[[ -z "$cmd" ]] && exit 0

log_block() {
  mkdir -p "$(dirname "$INCIDENT_LOG")"
  jq -cn --arg ts "$(date -Iseconds)" --arg cmd "$cmd" --arg group "$1" \
    '{timestamp: $ts, command: $cmd, status: "BLOCKED", pattern_matched: $group}' \
    >> "$INCIDENT_LOG"
}

shopt -s nocasematch
while IFS=$'\t' read -r group pattern; do
  if [[ "$cmd" == *"$pattern"* ]]; then
    log_block "$group"
    fail "bloqué [$group] motif « $pattern ». Demander une confirmation explicite à l'utilisateur."
  fi
done < <(jq -r '.patterns[] | . as $g | $g.patterns[] | [$g.name, .] | @tsv' "$PATTERNS_FILE")

exit 0
