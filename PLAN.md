# PLAN COMPLET : Agent Safety Architecture
## Résoudre définitivement les incidents destructifs

**Objectif Final :** Un agent autonome qui ne peut JAMAIS lancer d'action destructive sans validation humaine explicite.

**Timeline :** 3 phases (2 jours de travail)
- Phase 1 (4h) : Mémoire + Whitelist
- Phase 2 (4h) : Préfiltre déterministe
- Phase 3 (4h) : Sandbox + Tests

---

## PHASE 1 : Memory + Whitelist Foundation (4h)

### Étape 1.1 : Créer Safety Memory Storage
**Livrable :** `/Volumes/logousb/SSD/Projects/.claude/safety/` structure

```bash
# Pseudo-code : Ce que le script doit faire
mkdir -p /Volumes/logousb/SSD/Projects/.claude/safety/{rules,incidents,logs}

# Files:
# - rules/destructive-patterns.json (patterns à bloquer)
# - rules/memory-requirements.md (ce qu'il FAUT vérifier)
# - incidents/log.jsonl (incident timeline)
# - logs/agent-execution.log (audit trace)
```

**Action-guard.sh usage :**
```
./action-guard.sh \
  --action "create-safety-dirs" \
  --impact "Crée structure pour guardrails" \
  --rollback "rm -rf /Volumes/logousb/SSD/Projects/.claude/safety"
```

**Livrable concret :** Script `/Volumes/logousb/SSD/Projects/scripts/01-setup-safety-dirs.sh`

---

### Étape 1.2 : Initialiser destructive-patterns.json
**Livrable :** `/Volumes/logousb/SSD/Projects/.claude/safety/rules/destructive-patterns.json`

```json
{
  "version": "1.0",
  "patterns": [
    {
      "name": "HDD6-Live-Data",
      "severity": "CRITICAL",
      "patterns": ["rm -rf /Volumes/HDD6", "DROP SCHEMA", "docker compose down"],
      "reason": "HDD6 contains live Immich data — never destructive",
      "approved_actions": ["read", "ls", "docker exec with read-only"]
    },
    {
      "name": "Production-Containers",
      "severity": "CRITICAL",
      "patterns": ["docker compose down", "docker rm immich", "systemctl stop"],
      "reason": "Containers running production — requires explicit approval",
      "approved_actions": ["docker logs", "docker stats", "curl health check"]
    },
    {
      "name": "Database-Operations",
      "severity": "CRITICAL",
      "patterns": ["DROP", "DELETE FROM", "TRUNCATE", "ALTER TABLE"],
      "reason": "DB modifications are irreversible",
      "approved_actions": ["SELECT", "BACKUP via pg_dump"]
    }
  ]
}
```

**Action-guard.sh usage :**
```
./action-guard.sh \
  --action "create-destructive-patterns" \
  --impact "Définit patterns à bloquer (HDD6, DB, containers)" \
  --rollback "rm /Volumes/logousb/SSD/Projects/.claude/safety/rules/destructive-patterns.json"
```

**Livrable concret :** Script `/Volumes/logousb/SSD/Projects/scripts/02-init-destructive-patterns.sh`

---

### Étape 1.3 : Créer Memory Requirements Checklist
**Livrable :** `/Volumes/logousb/SSD/Projects/.claude/safety/rules/memory-requirements.md`

```markdown
# Memory Consultation Requirements

## Avant CHAQUE action destructive, agent DOIT :

### 1. READ destructive-patterns.json
- Vérifier si la command est dans les patterns
- Si CRITICAL → force confirmation

### 2. READ incidents/log.jsonl
- Vérifier les incidents précédents
- Si incident similaire → force escalade

### 3. READ CLAUDE.md
- Vérifier le plan actuel
- Si déviation → flag warning

### 4. COMPUTE checksum de context
- Avant et après action
- Audit trail immédiate

## Exemple Exécution Correcte :
```
[MEMORY-CHECK] Loading destructive-patterns.json ✓
[MEMORY-CHECK] Scanning for "DROP SCHEMA" pattern...
[PATTERN-MATCH] FOUND in destructive-patterns.json (CRITICAL)
[ACTION-BLOCK] Destructive action detected
[APPROVAL-REQUIRED] User must type: CONFIRM DB DESTRUCTIVE
```

## Exemple Exécution CASSÉE (ce qu'il ne faut PAS faire) :
```
[SKIP] Pas de vérification mémoire
[BASH] docker exec ... "DROP SCHEMA public CASCADE"
[RESULT] 🔴 Database cassée
```
```

**Action-guard.sh usage :**
```
./action-guard.sh \
  --action "create-memory-checklist" \
  --impact "Définit ce qu'agent DOIT vérifier avant destructive" \
  --rollback "rm /Volumes/logousb/SSD/Projects/.claude/safety/rules/memory-requirements.md"
```

**Livrable concret :** Script `/Volumes/logousb/SSD/Projects/scripts/03-init-memory-requirements.sh`

---

### Étape 1.4 : Configurer Whitelist Tools dans settings.json
**Livrable :** Mise à jour `~/.claude/settings.json` (ou créer si inexistant)

```json
{
  "agent-whitelist": {
    "enabled": true,
    "version": "1.0",
    "allowed-tools": [
      "read",
      "bash-safe",
      "docker-exec-ro",
      "curl-api",
      "sql-select-only"
    ],
    "blocked-tools": [
      "bash-unrestricted",
      "docker-full",
      "sql-destructive",
      "file-write-hdd6"
    ],
    "destructive-confirmation": {
      "required": true,
      "type": "explicit-text-match",
      "examples": [
        "CONFIRM DB DELETE: type this exactly",
        "CONFIRM HDD6 DESTRUCTIVE: type this exactly"
      ]
    }
  }
}
```

**Action-guard.sh usage :**
```
./action-guard.sh \
  --action "update-settings-whitelist" \
  --impact "Restrict agent tools to safe subset + require confirmation" \
  --rollback "revert settings.json to backup"
```

**Livrable concret :** Script `/Volumes/logousb/SSD/Projects/scripts/04-configure-whitelist.sh`

---

## PHASE 2 : Deterministic Blocker (4h)

### Étape 2.1 : Créer Pre-Execution Hook Script
**Livrable :** `/Volumes/logousb/SSD/Projects/hooks/pre-execution-guard.sh`

```bash
#!/bin/bash
# Pre-execution guard : bloque patterns destructives AVANT exécution

DESTRUCTIVE_PATTERNS_FILE="/Volumes/logousb/SSD/Projects/.claude/safety/rules/destructive-patterns.json"
INCIDENT_LOG="/Volumes/logousb/SSD/Projects/.claude/safety/incidents/log.jsonl"

detect_destructive_pattern() {
  local command="$1"
  
  # Parse destructive-patterns.json et vérifier
  patterns=$(jq -r '.patterns[].patterns[]' "$DESTRUCTIVE_PATTERNS_FILE")
  
  while IFS= read -r pattern; do
    if [[ "$command" == *"$pattern"* ]]; then
      echo "BLOCKED: Pattern detected: $pattern"
      log_incident "$command" "BLOCKED"
      return 1  # Block
    fi
  done <<< "$patterns"
  
  return 0  # Allow
}

require_confirmation() {
  local action="$1"
  local confirmation_type="$2"
  
  echo "⚠️  DESTRUCTIVE ACTION DETECTED"
  echo "Action: $action"
  echo "To confirm, type: $confirmation_type"
  read -p "> " user_input
  
  if [[ "$user_input" != "$confirmation_type" ]]; then
    echo "❌ Confirmation failed. Action blocked."
    log_incident "$action" "CANCELLED"
    return 1
  fi
  
  return 0
}

log_incident() {
  local command="$1"
  local status="$2"
  
  echo "{\"timestamp\": \"$(date -Iseconds)\", \"command\": \"$command\", \"status\": \"$status\"}" >> "$INCIDENT_LOG"
}

# MAIN
COMMAND_TO_RUN="$1"
if ! detect_destructive_pattern "$COMMAND_TO_RUN"; then
  exit 1
fi

# If pattern found, require explicit confirmation
if echo "$COMMAND_TO_RUN" | grep -E "DROP|DELETE|rm -rf|docker.*down"; then
  if ! require_confirmation "$COMMAND_TO_RUN" "CONFIRM DESTRUCTIVE"; then
    exit 1
  fi
fi

exit 0
```

**Action-guard.sh usage :**
```
./action-guard.sh \
  --action "deploy-pre-execution-hook" \
  --impact "Intercept all bash commands, block destructive patterns before execution" \
  --rollback "rm /Volumes/logousb/SSD/Projects/hooks/pre-execution-guard.sh"
```

**Livrable concret :** Script `/Volumes/logousb/SSD/Projects/scripts/05-deploy-blocker.sh`

---

### Étape 2.2 : Intégrer Hook dans Claude Code
**Livrable :** Settings.json update pour appeler hook

```json
{
  "hooks": {
    "before-bash": {
      "script": "/Volumes/logousb/SSD/Projects/hooks/pre-execution-guard.sh",
      "params": ["${command}"],
      "block-on-failure": true
    }
  }
}
```

**Action-guard.sh usage :**
```
./action-guard.sh \
  --action "integrate-hook-settings" \
  --impact "Claude Code will call pre-execution-guard before every bash command" \
  --rollback "revert settings.json"
```

**Livrable concret :** Script `/Volumes/logousb/SSD/Projects/scripts/06-integrate-hook.sh`

---

## PHASE 3 : Validation & Hardening (4h)

### Étape 3.1 : Test Suite
**Livrable :** `/Volumes/logousb/SSD/Projects/tests/agent-safety-tests.sh`

```bash
#!/bin/bash
# Test suite : vérifier que les garde-fous marchent

test_1_block_drop_schema() {
  echo "TEST 1: Block DROP SCHEMA"
  if /Volumes/logousb/SSD/Projects/hooks/pre-execution-guard.sh "docker exec ... DROP SCHEMA public CASCADE"; then
    echo "❌ FAIL: Should have blocked DROP SCHEMA"
    return 1
  else
    echo "✅ PASS: Correctly blocked DROP SCHEMA"
    return 0
  fi
}

test_2_block_rm_hdd6() {
  echo "TEST 2: Block rm -rf /Volumes/HDD6"
  if /Volumes/logousb/SSD/Projects/hooks/pre-execution-guard.sh "rm -rf /Volumes/HDD6/02-Chaude/immich"; then
    echo "❌ FAIL: Should have blocked rm -rf"
    return 1
  else
    echo "✅ PASS: Correctly blocked rm -rf"
    return 0
  fi
}

test_3_allow_read() {
  echo "TEST 3: Allow safe read"
  if /Volumes/logousb/SSD/Projects/hooks/pre-execution-guard.sh "ls -la /Volumes/HDD6/02-Chaude/immich-v3"; then
    echo "✅ PASS: Correctly allowed safe read"
    return 0
  else
    echo "❌ FAIL: Should have allowed safe read"
    return 1
  fi
}

test_4_require_confirmation() {
  echo "TEST 4: Require explicit confirmation for destructive"
  # This test requires interactive input — skip in automation
  echo "⚠️  SKIP: Requires manual confirmation"
  return 0
}

# RUN ALL
test_1_block_drop_schema
test_2_block_rm_hdd6
test_3_allow_read
test_4_require_confirmation
```

**Action-guard.sh usage :**
```
./action-guard.sh \
  --action "run-safety-tests" \
  --impact "Validate that blocker works correctly" \
  --rollback "None needed (read-only tests)"
```

**Livrable concret :** Script `/Volumes/logousb/SSD/Projects/scripts/07-run-tests.sh`

---

### Étape 3.2 : Incident Log Review & Memory Update
**Livrable :** Script review incidents et update mémoire

```bash
#!/bin/bash
# Après chaque test/incident : log + mettre à jour mémoire

INCIDENT_LOG="/Volumes/logousb/SSD/Projects/.claude/safety/incidents/log.jsonl"
MEMORY_FILE="/Users/logo/.claude/projects/-Volumes-logousb-SSD-Projects/memory/MEMORY.md"

review_incidents() {
  echo "=== Recent Incidents ==="
  tail -10 "$INCIDENT_LOG"
  
  # Count by status
  echo ""
  echo "=== Incident Summary ==="
  jq -r '.status' "$INCIDENT_LOG" | sort | uniq -c
}

update_memory_with_patterns() {
  local new_pattern="$1"
  local incident_count=$(wc -l < "$INCIDENT_LOG")
  
  # Append to MEMORY.md
  echo "- 🔒 [Safety Blocker Active] — $incident_count incidents logged, $new_pattern added" >> "$MEMORY_FILE"
}

review_incidents
```

**Action-guard.sh usage :**
```
./action-guard.sh \
  --action "review-incidents-update-memory" \
  --impact "Log all incidents, update memory with learnings" \
  --rollback "Remove recent entries from MEMORY.md"
```

**Livrable concret :** Script `/Volumes/logousb/SSD/Projects/scripts/08-review-incidents.sh`

---

### Étape 3.3 : Docker Sandbox Setup (Optional Long-term)
**Livrable :** Dockerfile pour agent sandboxé

```dockerfile
FROM ubuntu:22.04
# Minimal agent runner : no root, restricted filesystem

RUN groupadd -r agent && useradd -r -g agent agent
WORKDIR /work

# Copy only safe tools
COPY --chown=agent:agent .claude/safety /work/safety
COPY --chown=agent:agent hooks /work/hooks
COPY --chown=agent:agent scripts /work/scripts

# Restrict filesystem
RUN chmod 750 /work && \
    chmod 550 /work/hooks && \
    chmod 550 /work/scripts

USER agent
# No sudo, no docker, no privileged access
```

**Action-guard.sh usage :**
```
./action-guard.sh \
  --action "deploy-sandbox-dockerfile" \
  --impact "Build isolated agent container with minimal privileges" \
  --rollback "Remove Dockerfile, cleanup built image"
```

**Livrable concret :** Script `/Volumes/logousb/SSD/Projects/scripts/09-build-sandbox.sh`

---

## EXECUTION CHECKLIST

### Pre-Execution (Before Any Phase)
- [ ] Read this entire plan
- [ ] Understand each livrable
- [ ] Backup settings.json + MEMORY.md
- [ ] Have action-guard.sh ready

### Phase 1 Execution (4h)
```bash
# Step by step, with action-guard.sh for each

./action-guard.sh --action "phase-1-setup" ...
/Volumes/logousb/SSD/Projects/scripts/01-setup-safety-dirs.sh
/Volumes/logousb/SSD/Projects/scripts/02-init-destructive-patterns.sh
/Volumes/logousb/SSD/Projects/scripts/03-init-memory-requirements.sh
./action-guard.sh --action "phase-1-update-whitelist" ...
/Volumes/logousb/SSD/Projects/scripts/04-configure-whitelist.sh
```

### Phase 2 Execution (4h)
```bash
./action-guard.sh --action "phase-2-blocker-deploy" ...
/Volumes/logousb/SSD/Projects/scripts/05-deploy-blocker.sh
./action-guard.sh --action "phase-2-hook-integration" ...
/Volumes/logousb/SSD/Projects/scripts/06-integrate-hook.sh
```

### Phase 3 Execution (4h)
```bash
./action-guard.sh --action "phase-3-testing" ...
/Volumes/logousb/SSD/Projects/scripts/07-run-tests.sh
/Volumes/logousb/SSD/Projects/scripts/08-review-incidents.sh

# Optional (long-term)
./action-guard.sh --action "phase-3-sandbox" ...
/Volumes/logousb/SSD/Projects/scripts/09-build-sandbox.sh
```

---

## SUCCESS CRITERIA

✅ Phase 1 Done :
- [ ] Memory files created
- [ ] Destructive patterns defined
- [ ] Whitelist configured in settings.json

✅ Phase 2 Done :
- [ ] Pre-execution hook script deployed
- [ ] Hook integrated into Claude Code
- [ ] Hook tested manually

✅ Phase 3 Done :
- [ ] All tests pass
- [ ] Incidents logged in /incidents/log.jsonl
- [ ] Memory updated with learnings
- [ ] No manual bypass possible

---

## LONG-TERM MAINTENANCE

**Weekly :** Review incidents log, update destructive-patterns.json
**Monthly :** Run full test suite, update MEMORY.md
**Per-Incident :** Log → Memory → Test → Validate

---

## REFERENCES

- `/Volumes/logousb/SSD/Projects/action-guard.sh` — Always use before destructive
- `/Volumes/logousb/SSD/Projects/CLAUDE.md` — Project rules
- Research findings : SafeMCP, ToolSafe, Constitutional AI papers

---

**Plan créé :** 2026-10-15
**Objectif :** Zéro incident destructif après Phase 3 ✅
