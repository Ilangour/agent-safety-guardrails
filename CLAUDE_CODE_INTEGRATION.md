# Claude Code Integration Guide

**Enable agent safety guardrails in Claude Code in 5 minutes.**

This guide walks you through integrating the Agent Safety Guardrails framework into Claude Code to prevent destructive agent actions.

---

## What This Does

After integration:
- ✅ Every `bash` command is checked against destructive patterns
- ✅ Dangerous commands are **BLOCKED** before execution
- ✅ Confirmation is **REQUIRED** for destructive operations
- ✅ Every incident is **LOGGED** with timestamp
- ✅ Agent must **CONSULT MEMORY** before acting

---

## Prerequisites

- Claude Code installed
- `git` installed
- `jq` installed (for JSON parsing)

---

## Installation (5 Steps)

### Step 1: Clone the Agent Safety Guardrails Repo

```bash
# Choose a location for the framework
# Option A: In your projects directory
cd ~/Projects
git clone https://github.com/loicgo29/agent-safety-guardrails
cd agent-safety-guardrails

# Option B: In Claude Code's config directory
cd ~/.claude
git clone https://github.com/loicgo29/agent-safety-guardrails
cd agent-safety-guardrails
```

**Recommended:** Option A (keep it separate from Claude config)

```bash
mkdir -p ~/Projects
cd ~/Projects
git clone https://github.com/loicgo29/agent-safety-guardrails
```

### Step 2: Copy Framework Files to Your Location

From the cloned repo, identify the full path to `pre-execution-guard.sh`:

```bash
# Get absolute path
GUARD_SCRIPT="$(pwd)/hooks/pre-execution-guard.sh"
echo $GUARD_SCRIPT

# Output should be something like:
# /Users/yourname/Projects/agent-safety-guardrails/hooks/pre-execution-guard.sh
```

Copy this path — you'll need it in Step 4.

### Step 3: Create Claude Code Settings File (if needed)

Claude Code reads settings from `~/.claude/settings.json`.

Check if it exists:

```bash
ls -la ~/.claude/settings.json
```

If it doesn't exist, create it:

```bash
mkdir -p ~/.claude
touch ~/.claude/settings.json
```

### Step 4: Add Hook Configuration to settings.json

Edit `~/.claude/settings.json` and add the hook config:

```json
{
  "hooks": {
    "before-bash": {
      "enabled": true,
      "script": "/Users/yourname/Projects/agent-safety-guardrails/hooks/pre-execution-guard.sh",
      "block-on-failure": true,
      "patterns-file": "/Users/yourname/Projects/agent-safety-guardrails/rules/destructive-patterns.json",
      "memory-file": "/Users/yourname/Projects/agent-safety-guardrails/rules/memory-requirements.md"
    }
  }
}
```

**IMPORTANT:** Replace `/Users/yourname/Projects/...` with your actual path from Step 2.

### Step 5: Verify Integration

Restart Claude Code and test:

```bash
# This should be ALLOWED (safe command)
ls -la ~

# This should be BLOCKED (destructive pattern)
rm -rf /tmp/test-delete
```

You should see:

```
⚠️  DESTRUCTIVE ACTION DETECTED
Action: rm -rf /tmp/test-delete
To confirm, type: CONFIRM DESTRUCTIVE
```

Type anything other than `CONFIRM DESTRUCTIVE` and the command will be blocked.

---

## Configuration Options

### Minimal Setup (Recommended for First-Time)

```json
{
  "hooks": {
    "before-bash": {
      "script": "/path/to/pre-execution-guard.sh",
      "block-on-failure": true
    }
  }
}
```

This uses default paths (relative to the script location).

### Full Setup (Advanced)

```json
{
  "hooks": {
    "before-bash": {
      "enabled": true,
      "script": "/path/to/pre-execution-guard.sh",
      "block-on-failure": true,
      "patterns-file": "/path/to/destructive-patterns.json",
      "memory-file": "/path/to/memory-requirements.md",
      "incident-log": "/path/to/incidents/log.jsonl",
      "timeout-seconds": 5,
      "confirmation-type": "CONFIRM DESTRUCTIVE"
    }
  }
}
```

### Testing Mode (Temporary)

```json
{
  "hooks": {
    "before-bash": {
      "enabled": true,
      "script": "/path/to/pre-execution-guard.sh",
      "block-on-failure": false,
      "log-only": true
    }
  }
}
```

This logs violations but doesn't block. Useful for testing before full enforcement.

---

## Customization

### Add Your Own Destructive Patterns

Edit `rules/destructive-patterns.json`:

```json
{
  "name": "My-Custom-Patterns",
  "severity": "HIGH",
  "patterns": [
    "my-dangerous-command",
    "some-risky-operation"
  ],
  "reason": "This could break things",
  "approved_actions": ["safe-alternative-command"]
}
```

### Modify Confirmation Text

In `hooks/pre-execution-guard.sh`, change line:

```bash
if [[ "$user_input" != "$required_text" ]]; then
```

To require a different confirmation, edit `memory-requirements.md`:

```markdown
To confirm, type: YOUR_CUSTOM_TEXT
```

---

## Monitoring & Incidents

### View Blocked Actions

Incidents are logged to `incidents/log.jsonl`:

```bash
# View recent incidents
tail -20 incidents/log.jsonl

# Pretty-print incidents
jq . incidents/log.jsonl | tail -50

# Count by status
jq -r '.status' incidents/log.jsonl | sort | uniq -c
```

### Example Incident Log

```json
{
  "timestamp": "2026-10-15T21:45:32+02:00",
  "command": "DROP SCHEMA public CASCADE",
  "status": "BLOCKED",
  "pattern_matched": "Database-Destructive",
  "severity": "CRITICAL"
}
```

### Update Memory When Patterns Change

When you add new patterns, update `rules/memory-requirements.md`:

```markdown
## Updated Pattern Groups (as of 2026-10-15)

- Database-Destructive
- Filesystem-Destructive
- Container-Control
- System-Control
- Live-Archive-Protection
- Process-Kill
- **My-Custom-Patterns** ← NEW
```

---

## Troubleshooting

### Hook Not Being Called

**Symptom:** Commands run without any prompt

**Fix:**
1. Restart Claude Code
2. Verify `~/.claude/settings.json` has correct syntax (run `jq . ~/.claude/settings.json`)
3. Check that script path is absolute, not relative
4. Ensure `pre-execution-guard.sh` is executable: `chmod +x <script-path>`

### "Patterns file not found"

**Symptom:** Warning about missing destructive-patterns.json

**Fix:**
1. Verify the file exists: `ls -la /path/to/destructive-patterns.json`
2. Check the path in settings.json is correct
3. Make sure path is absolute, not relative

### Commands Getting Blocked Unexpectedly

**Symptom:** Safe commands like `ls` are blocked

**Fix:**
1. Review `destructive-patterns.json` for overly broad patterns
2. Check incident log to see which pattern matched
3. Narrow the pattern in the JSON file

Example: `"ls"` as a pattern is too broad — use `"ls -R"` or `"ls /"` instead.

### Confirmation Text Mismatch

**Symptom:** Entering `CONFIRM DESTRUCTIVE` doesn't work

**Fix:**
1. Check you're typing exactly: `CONFIRM DESTRUCTIVE`
2. No extra spaces, exact case matching
3. Verify the text in `memory-requirements.md`

---

## Examples

### Example 1: Blocking a Real-World Incident

**Scenario:** Agent tries to delete Immich data

```bash
# Agent runs this command (autonomously)
rm -rf /Volumes/HDD6/02-Chaude/immich

# Claude Code intercepts:
⚠️  DESTRUCTIVE ACTION DETECTED
Action: rm -rf /Volumes/HDD6/02-Chaude/immich
To confirm, type: CONFIRM DESTRUCTIVE

# You (human) see the prompt and type "no" or press Ctrl+C
# → Command is BLOCKED
# → Incident is logged
# → Agent cannot proceed without your approval
```

### Example 2: Allowing Safe Commands

```bash
# Agent runs this command
docker logs immich_server

# No pattern match in destructive-patterns.json
# → Command ALLOWED immediately
# → No prompt, no delay
```

### Example 3: Approving a Necessary Destructive Operation

```bash
# Agent runs this (after human-approved decision)
docker compose down

# Claude Code intercepts:
⚠️  DESTRUCTIVE ACTION DETECTED
Action: docker compose down
To confirm, type: CONFIRM DESTRUCTIVE

# You (human) review and decide it's safe
# You type: CONFIRM DESTRUCTIVE
# → Command ALLOWED
# → Incident logged as APPROVED
# → Docker compose shuts down cleanly
```

---

## Integration with CI/CD (Optional)

### GitHub Actions

Add to your `.github/workflows/test.yml`:

```yaml
- name: Validate agent safety
  run: |
    ./agent-safety-guardrails/tests/agent-safety-tests.sh
```

### Pre-Commit Hook

Create `.git/hooks/pre-commit`:

```bash
#!/bin/bash
# Validate no destructive patterns in staged code
jq . agent-safety-guardrails/rules/destructive-patterns.json > /dev/null
```

---

## Updating the Framework

The framework is a Git repository. Keep it updated:

```bash
cd ~/Projects/agent-safety-guardrails
git pull origin main
```

New pattern groups or memory updates will be available immediately.

---

## Disable Temporarily (Advanced)

If you need to temporarily bypass guardrails:

```json
{
  "hooks": {
    "before-bash": {
      "enabled": false
    }
  }
}
```

⚠️ **Warning:** Do this only for testing. Re-enable immediately after.

---

## Security Notes

- ✅ The blocker runs **before** any command execution
- ✅ Patterns are checked **before** you confirm
- ✅ Confirmation is **explicit text match**, not just yes/no
- ✅ All incidents are **logged immutably**
- ✅ Framework itself is **open source** (audit it)

---

## Get Help

### For Questions About This Integration
- Read [PLAN.md](PLAN.md) for the 3-phase implementation plan
- See [README.md](README.md) for framework overview
- Check [memory-requirements.md](rules/memory-requirements.md) for agent decision-making rules

### To Report Issues
1. Check the incident log: `tail -20 incidents/log.jsonl`
2. Verify your settings.json syntax
3. Open an issue on GitHub: https://github.com/loicgo29/agent-safety-guardrails/issues

### To Contribute Patterns
See [CONTRIBUTING.md](CONTRIBUTING.md) for how to submit new destructive patterns you've discovered.

---

## Summary

After integration:

| Action | Before | After |
|--------|--------|-------|
| `ls` (safe) | Runs immediately | Runs immediately ✅ |
| `rm -rf` | Runs immediately 🚨 | Blocked, confirmation required ✅ |
| `docker compose down` | Runs immediately 🚨 | Blocked, confirmation required ✅ |
| `DROP SCHEMA` | Runs immediately 🚨 | Blocked, confirmation required ✅ |
| Incident tracking | No audit trail | Logged to incidents/log.jsonl ✅ |

---

**You're now protected. Agents cannot launch destructive commands without your explicit approval.**

Last Updated: 2026-10-15
