# Memory Consultation Requirements

## Rule: Mandatory Memory Check Before Destructive Action

**Every agent MUST consult this memory before ANY destructive operation.**

Not optional. Not "if you feel like it." MANDATORY.

---

## Pre-Execution Checklist

Before launching ANY command that touches:
- Files (rm, cp, mv)
- Databases (DROP, DELETE, ALTER)
- Containers (docker compose down, docker kill)
- Systems (systemctl, kill -9)

**Agent MUST:**

### 1. READ destructive-patterns.json
```
File: rules/destructive-patterns.json
Check: Does my command match ANY pattern in the list?
If YES:
  → BLOCK immediately
  → Require explicit human confirmation
  → Log incident with timestamp
If NO:
  → Continue to step 2
```

### 2. READ this file (memory-requirements.md)
```
You're reading it right now.
Reminder: You MUST follow this checklist.
No exceptions. No "I'm in autonomy mode."
```

### 3. VERIFY the context
```
Ask yourself:
- What is the impact of this action?
- Can it be undone?
- Is there a backup?
- Who approved this?
- Have I logged it?

If unsure → BLOCK and ask human
```

### 4. LOG the decision
```
File: incidents/log.jsonl
Format: {"timestamp": "...", "command": "...", "status": "APPROVED|BLOCKED|CANCELLED"}
```

---

## Examples: Correct vs Incorrect Execution

### ❌ INCORRECT (What NOT to do)

```bash
# Agent thinks: "I'm in autonomy mode, just continue"
docker compose down  # NO MEMORY CHECK
→ Services crash
→ Data corrupted
→ Incident not logged
```

### ✅ CORRECT (What TO do)

```bash
# Agent thinks: "This is destructive, check memory first"
1. READ destructive-patterns.json
2. FIND: "docker compose down" matches Container-Control pattern
3. SEVERITY: HIGH
4. ACTION: BLOCK + require confirmation
5. REQUIRE: User types "CONFIRM DESTRUCTIVE"
6. LOG: {"timestamp": "...", "command": "docker compose down", "status": "BLOCKED"}
7. Wait for approval
```

---

## Critical Guardrails

### HDD6 Live Data
```
Path: /Volumes/HDD6/02-Chaude/immich/
Status: LIVE PRODUCTION DATA
Rule: NEVER destructive operation on this path
Approved Actions: Read, Backup, Analyze only
```

### Database Operations
```
Action: DROP SCHEMA, DELETE FROM, TRUNCATE
Status: IRREVERSIBLE
Rule: Require confirmation every single time
Even if you have a backup, still require confirmation
```

### Container Orchestration
```
Action: docker compose down, docker stop
Status: Interrupts services
Rule: Require confirmation + log reason
```

---

## The Circuit Breaker Rule

**If agent launches destructive without checking memory → CIRCUIT BREAKER activates:**

1. Pre-execution hook detects pattern
2. Command is BLOCKED immediately
3. Confirmation is REQUIRED
4. Incident is LOGGED
5. Retry only after human approval

---

## What Happens If You Skip This

| If You Skip | Consequence |
|---|---|
| Don't check patterns | Hook catches it anyway (2nd layer) |
| Don't require confirmation | Hook forces it anyway |
| Don't log incident | Audit trail is broken |
| Think "it's just one time" | That's how incidents start |

---

## Memory Persistence

This file is **permanent, immutable, and non-negotiable.**

It is not:
- A guideline (it's a requirement)
- A suggestion (it's a rule)
- A nice-to-have (it's mandatory)
- Bypassable in "autonomy mode" (there is no such exemption)

---

## Incident Recovery

If incident occurs despite checklist:

1. **Immediate:** Log in incidents/log.jsonl
2. **Short-term:** Understand what went wrong
3. **Long-term:** Update destructive-patterns.json to prevent recurrence
4. **Verify:** Re-run tests to ensure patterns catch it next time

---

## How To Use This

### For Agent Developers
```python
# Before any destructive operation:
if agent.is_destructive(command):
    if not agent.consulted_memory("memory-requirements.md"):
        raise RequiredMemoryCheckFailed()
    if not agent.found_pattern_match(command):
        raise PatternNotFound()
    if not agent.got_human_confirmation():
        raise ConfirmationRequired()
    agent.log_incident(command, "APPROVED")
```

### For Claude Code Integration
```json
{
  "hooks": {
    "before-bash": {
      "script": "pre-execution-guard.sh",
      "memory-check": "rules/memory-requirements.md",
      "patterns": "rules/destructive-patterns.json"
    }
  }
}
```

---

## Last Updated
2026-10-15

**Status:** Active, Non-negotiable, Enforced by pre-execution-guard.sh
