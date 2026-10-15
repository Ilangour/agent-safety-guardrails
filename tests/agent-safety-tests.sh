#!/bin/bash
# Test suite for hooks/pre-execution-guard.sh (Claude Code PreToolUse contract).
# Runs against a copy of the hook and rules so the real incidents log is not touched.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/hooks" "$WORK/rules"
cp "$SCRIPT_DIR/hooks/pre-execution-guard.sh" "$WORK/hooks/"
cp "$SCRIPT_DIR/rules/destructive-patterns.json" "$WORK/rules/"
GUARD_SCRIPT="$WORK/hooks/pre-execution-guard.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

test_count=0
passed=0
failed=0

run_test() {
  local name="$1"
  local command="$2"
  local should_block="$3"
  local rc

  test_count=$((test_count + 1))
  jq -cn --arg c "$command" '{tool_name: "Bash", tool_input: {command: $c}}' \
    | "$GUARD_SCRIPT" >/dev/null 2>&1
  rc=$?

  echo "TEST $test_count: $name"
  if [[ "$should_block" == "yes" && $rc -eq 2 ]] || [[ "$should_block" == "no" && $rc -eq 0 ]]; then
    echo -e "  ${GREEN}PASS${NC} (exit $rc)"
    passed=$((passed + 1))
  else
    echo -e "  ${RED}FAIL${NC} (exit $rc, expected $([[ $should_block == yes ]] && echo 2 || echo 0))"
    failed=$((failed + 1))
  fi
}

echo "Agent Safety Guardrails test suite"

run_test "Block DROP SCHEMA" "docker exec db psql -c 'DROP SCHEMA public CASCADE'" yes
run_test "Block rm -rf on HDD6" "rm -rf /Volumes/HDD6/critical-data" yes
run_test "Block docker compose down" "docker compose down" yes
run_test "Block docker volume rm" "docker volume rm test-volume" yes
run_test "Block docker rm through sh -c" "sh -c 'docker rm web'" yes
run_test "Block TRUNCATE TABLE" "psql -c 'TRUNCATE TABLE users'" yes
run_test "Allow docker ps" "docker ps" no
run_test "Allow docker volume ls" "docker volume ls" no
run_test "Allow ls on HDD6" "ls -la /Volumes/HDD6/data" no
run_test "Allow curl GET" "curl -s http://localhost:8080/health" no

echo ""
echo "Results: $passed passed, $failed failed ($test_count total)"

[[ $failed -eq 0 ]]
