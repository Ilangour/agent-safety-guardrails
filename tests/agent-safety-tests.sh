#!/bin/bash
# Test suite: verify guardrails work correctly

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD_SCRIPT="${SCRIPT_DIR}/hooks/pre-execution-guard.sh"
PATTERNS_FILE="${SCRIPT_DIR}/rules/destructive-patterns.json"

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
  
  ((test_count++))
  
  echo ""
  echo "TEST $test_count: $name"
  echo "Command: $command"
  
  if "$GUARD_SCRIPT" "$command" > /dev/null 2>&1; then
    if [[ "$should_block" == "no" ]]; then
      echo -e "${GREEN}✅ PASS${NC} (correctly allowed)"
      ((passed++))
    else
      echo -e "${RED}❌ FAIL${NC} (should have blocked)"
      ((failed++))
    fi
  else
    if [[ "$should_block" == "yes" ]]; then
      echo -e "${GREEN}✅ PASS${NC} (correctly blocked)"
      ((passed++))
    else
      echo -e "${RED}❌ FAIL${NC} (should have allowed)"
      ((failed++))
    fi
  fi
}

echo "=========================================="
echo "Agent Safety Guardrails Test Suite"
echo "=========================================="

# Run tests
run_test "Block DROP SCHEMA" \
  "docker exec ... DROP SCHEMA public CASCADE" \
  "yes"

run_test "Block rm -rf /critical" \
  "rm -rf /Volumes/HDD6/critical-data" \
  "yes"

run_test "Block docker compose down" \
  "docker compose down" \
  "yes"

run_test "Allow safe read" \
  "ls -la /Volumes/HDD6/data" \
  "no"

run_test "Allow curl GET" \
  "curl -s http://localhost:8080/health" \
  "no"

run_test "Block TRUNCATE TABLE" \
  "psql -c 'TRUNCATE TABLE users'" \
  "yes"

echo ""
echo "=========================================="
echo "Results: $passed passed, $failed failed ($test_count total)"
echo "=========================================="

if [[ $failed -eq 0 ]]; then
  echo -e "${GREEN}✅ All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}❌ Some tests failed${NC}"
  exit 1
fi
