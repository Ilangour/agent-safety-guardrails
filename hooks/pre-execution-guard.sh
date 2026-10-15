#!/bin/bash
# Pre-execution guard: blocks destructive patterns BEFORE execution
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTRUCTIVE_PATTERNS_FILE="${SCRIPT_DIR}/rules/destructive-patterns.json"
INCIDENT_LOG="${SCRIPT_DIR}/incidents/log.jsonl"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

detect_destructive_pattern() {
  local command="$1"
  
  if [[ ! -f "$DESTRUCTIVE_PATTERNS_FILE" ]]; then
    echo -e "${YELLOW}⚠️  Patterns file not found: $DESTRUCTIVE_PATTERNS_FILE${NC}"
    return 0  # Allow if no patterns file
  fi
  
  # Check each pattern
  while IFS= read -r pattern; do
    if [[ "$command" == *"$pattern"* ]]; then
      return 1  # Block
    fi
  done < <(jq -r '.patterns[].patterns[]' "$DESTRUCTIVE_PATTERNS_FILE" 2>/dev/null || true)
  
  return 0  # Allow
}

require_confirmation() {
  local action="$1"
  local required_text="$2"
  
  echo ""
  echo -e "${RED}⚠️  DESTRUCTIVE ACTION DETECTED${NC}"
  echo "Action: $action"
  echo ""
  echo "To confirm, type: $required_text"
  read -p "> " user_input
  
  if [[ "$user_input" != "$required_text" ]]; then
    echo -e "${RED}❌ Confirmation failed. Action blocked.${NC}"
    log_incident "$action" "CANCELLED"
    return 1
  fi
  
  return 0
}

log_incident() {
  local command="$1"
  local status="$2"
  
  mkdir -p "$(dirname "$INCIDENT_LOG")"
  echo "{\"timestamp\": \"$(date -Iseconds)\", \"command\": \"$command\", \"status\": \"$status\"}" >> "$INCIDENT_LOG"
}

# MAIN
COMMAND_TO_RUN="$1"

if [[ -z "$COMMAND_TO_RUN" ]]; then
  echo "Usage: $0 <command>"
  exit 1
fi

# Check for destructive patterns
if ! detect_destructive_pattern "$COMMAND_TO_RUN"; then
  echo -e "${RED}BLOCKED: Destructive pattern detected${NC}"
  log_incident "$COMMAND_TO_RUN" "BLOCKED"
  
  # Require confirmation
  if ! require_confirmation "$COMMAND_TO_RUN" "CONFIRM DESTRUCTIVE"; then
    exit 1
  fi
  
  log_incident "$COMMAND_TO_RUN" "APPROVED"
fi

exit 0
