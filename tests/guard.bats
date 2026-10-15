#!/usr/bin/env bats
# Run: npx -y bats@1.13.0 tests/guard.bats
# Each corpus line is one Bash command fed to hooks/guard.sh as a real PreToolUse JSON.
# Runs against a copy of the hooks and rules so incidents/log.jsonl is not touched.

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  CORPUS="$BATS_TEST_DIRNAME/corpus"
  mkdir -p "$BATS_TEST_TMPDIR/hooks" "$BATS_TEST_TMPDIR/rules"
  cp "$ROOT"/hooks/*.sh "$BATS_TEST_TMPDIR/hooks/"
  cp "$ROOT"/rules/destructive-patterns.json "$BATS_TEST_TMPDIR/rules/"
  GUARD="$BATS_TEST_TMPDIR/hooks/guard.sh"
  export GUARD_LOG="$BATS_TEST_TMPDIR/decisions.jsonl"
  export CC_SAFETY_NET_HOME="$BATS_TEST_TMPDIR/ccsn-home"
}

# guard <command>: sets $status and $output (stdout only, stderr dropped)
guard() {
  status=0
  output="$(jq -nc --arg c "$1" --arg cwd "$BATS_TEST_TMPDIR" \
    '{session_id:"test",cwd:$cwd,permission_mode:"default",hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},tool_use_id:"toolu_test"}' \
    | "$GUARD" 2>/dev/null)" || status=$?
}
decision() { jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${output:-{\}}" 2>/dev/null; }

each_line() {  # each_line <file> <callback>; fails if any callback fails
  local line failed=0
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    "$2" "$line" || failed=1
  done <"$1"
  return $failed
}
expect_block() { guard "$1"; [[ $status -eq 2 && -z "$output" ]] || { echo "NOT BLOCKED (status=$status): $1"; return 1; }; }
expect_ask()   { guard "$1"; [[ $status -eq 0 && "$(decision)" == ask ]] || { echo "NOT ASK (status=$status): $1"; return 1; }; }
expect_allow() { guard "$1"; [[ $status -eq 0 && -z "$output" ]] || { echo "NOT ALLOWED (status=$status): $1"; return 1; }; }

@test "must_block: exit 2, nothing on stdout" {
  each_line "$CORPUS/must_block.txt" expect_block
}

@test "must_ask: exit 0, permissionDecision=ask" {
  each_line "$CORPUS/must_ask.txt" expect_ask
}

@test "must_allow: exit 0, empty stdout" {
  each_line "$CORPUS/must_allow.txt" expect_allow
}

@test "known_gaps: still allowed (move a line to must_block.txt once it is caught)" {
  closed=0
  still_open() { guard "$1"; [[ $status -eq 0 && -z "$output" ]] || { echo "gap closed: $1"; closed=1; }; }
  each_line "$CORPUS/known_gaps.txt" still_open
  [[ $closed -eq 0 ]]
  skip "$(grep -cv '^#\|^$' "$CORPUS/known_gaps.txt") known gaps, see tests/corpus/known_gaps.txt"
}

@test "false_positives: harmless but still blocked by the overlay (move a line to must_allow.txt once fixed)" {
  fixed=0
  still_blocked() { guard "$1"; [[ $status -eq 2 ]] || { echo "false positive fixed: $1"; fixed=1; }; }
  each_line "$CORPUS/false_positives.txt" still_blocked
  [[ $fixed -eq 0 ]]
  skip "$(grep -cv '^#\|^$' "$CORPUS/false_positives.txt") false positives, see tests/corpus/false_positives.txt"
}

@test "CC_SAFETY_NET_LEVEL=paranoid denies in-cwd recursive rm" {
  CC_SAFETY_NET_LEVEL=paranoid expect_block 'rm -rf ./build'
}

@test "garbage stdin: exit 2, nothing on stdout" {
  for bad in 'not json' '{}' ''; do
    status=0; output="$(printf '%s' "$bad" | "$GUARD" 2>/dev/null)" || status=$?
    [[ $status -eq 2 && -z "$output" ]] || { echo "input '$bad': status=$status"; return 1; }
  done
}

@test "engine unavailable: ask on sensitive keyword, never silent allow" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  for t in env bash jq grep date mkdir dirname cat; do ln -s "$(command -v $t)" "$BATS_TEST_TMPDIR/bin/$t"; done
  PATH="$BATS_TEST_TMPDIR/bin" expect_ask 'docker compose ps; terraform destroy'
  PATH="$BATS_TEST_TMPDIR/bin" expect_allow 'ls -la'
  PATH="$BATS_TEST_TMPDIR/bin" expect_block 'docker volume rm data'   # overlay still active
}

@test "decisions are logged as JSON lines, outside the repo" {
  guard 'git push --force'
  jq -e 'select(.decision=="deny" and .command=="git push --force" and .session=="test")' "$GUARD_LOG" >/dev/null
  ! grep -qs toolu_test "$ROOT/incidents/log.jsonl"
}
