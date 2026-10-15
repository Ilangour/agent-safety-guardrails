#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Reads the tool call as JSON on stdin.
# 1. cc-safety-net (MIT, pinned, strict mode) parses the command: shell-aware, unwraps
#    sudo/bash -c/$()/base64|sh, denies what it cannot parse.
# 2. pre-execution-guard.sh (this repo's own patterns) runs as a local overlay.
# 3. A few infra commands that are legal but irreversible are escalated to "ask".
# Each layer can only tighten the decision: deny > ask > allow.
#
# deny  -> reason on stderr, exit 2 (blocks even under bypassPermissions)
# ask   -> exit 0 + permissionDecision JSON (Claude Code's native prompt; no TTY here)
# allow -> exit 0, nothing on stdout. Nothing else is ever written to stdout.
set -uo pipefail

ENGINE_VERSION=2.6.12
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="${GUARD_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/agent-safety-guardrails/decisions.jsonl}"
ASK_OVERLAY='terraform +(destroy|apply)\b|lxc +(delete|restore)\b'
# Fallback when the engine cannot run at all (no node/npx): never allow these silently.
SENSITIVE='\brm\b|-delete|\bdd\b|\bgit\b.*(push|reset|clean)|\bdrop\b|\btruncate\b|\bdelete\b|compose|terraform|\blxc\b|\bsudo\b|base64|\bsh\b|\bbash\b|\beval\b|\bxargs\b|\bpython'

fail() { echo "agent-safety-guardrails: $1" >&2; exit 2; }
export CC_SAFETY_NET_LEVEL="${CC_SAFETY_NET_LEVEL:-strict}"

command -v jq >/dev/null 2>&1 || fail "jq est requis (brew install jq)"
input="$(cat)"
cmd="$(jq -er '.tool_input.command' <<<"$input" 2>/dev/null)" || fail "entrée JSON invalide, appel bloqué par précaution"
[[ -z "$cmd" ]] && exit 0

if command -v cc-safety-net >/dev/null 2>&1; then engine=(cc-safety-net)
else engine=(npx -y "cc-safety-net@${ENGINE_VERSION}"); fi

decision=allow; reason=""
if verdict="$(printf '%s' "$input" | "${engine[@]}" hook --coding-cli 2>/dev/null)"; then
  decision="$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${verdict:-{\}}" 2>/dev/null)" || decision=ask
  reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"${verdict:-{\}}" 2>/dev/null)" || reason="verdict du moteur illisible : confirmation humaine requise"
elif grep -Eiq "$SENSITIVE" <<<"$cmd"; then
  decision=ask; reason="moteur cc-safety-net indisponible (node/npx manquant ?), mot-clé sensible : confirmation humaine requise"
fi

if [[ "$decision" != deny ]]; then
  if ! overlay="$(printf '%s' "$input" | "$HERE/pre-execution-guard.sh" 2>&1 >/dev/null)"; then
    decision=deny; reason="${overlay#agent-safety-guardrails: }"
  elif [[ "$decision" == allow ]] && grep -Eiq "$ASK_OVERLAY" <<<"$cmd"; then
    decision=ask; reason="action d'infrastructure irréversible : confirmation humaine requise"
  fi
fi

mkdir -p "$(dirname "$LOG")" 2>/dev/null
jq -nc --arg ts "$(date -u +%FT%TZ)" --arg sid "$(jq -r '.session_id // ""' <<<"$input")" \
  --arg tid "$(jq -r '.tool_use_id // ""' <<<"$input")" --arg cwd "$(jq -r '.cwd // ""' <<<"$input")" \
  --arg cmd "$cmd" --arg d "$decision" --arg r "$reason" \
  '{ts:$ts,session:$sid,tool_use:$tid,cwd:$cwd,command:$cmd,decision:$d,reason:$r}' >>"$LOG" 2>/dev/null

case "$decision" in
  deny) fail "$reason" ;;
  ask)  jq -nc --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}' ;;
  *)    exit 0 ;;
esac
