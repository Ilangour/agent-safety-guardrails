# Agent Safety Guardrails

Deterministic guardrails for Claude Code: destructive commands are refused by Claude Code itself, not by the model's good intentions.

Last updated: 2026-10-15. The decisions below are the ones applied on the author's machine.

## Principle

A rule written in `CLAUDE.md` is text the model can ignore. The controls in this repo are executed by Claude Code:

| Layer | Mechanism | Weakness |
|---|---|---|
| 1. Deny rules | `permissions.deny` in `~/.claude/settings.json` | Bash rules match the command text: `sh -c '...'` or `/bin/rm` are not matched |
| 2. PreToolUse hook | Script reads the command as JSON on stdin, exits `2` to block | Substring matching: also blocks harmless text (see Hook) |
| 3. `CLAUDE.md` | Instructions | Not a control |

Deny rules and the hook are guardrails, not a security boundary. Real protection for data comes from backups, from not mounting the Docker socket into containers, and from keeping destructive operations out of the agent's reach.

## Policy

- **Destructive commands** are refused by deny rules (Docker, Colima, `rm`, `find`) and by the hook. The deny list is in [step 3](#3-add-the-deny-rules); the hook patterns are in `rules/destructive-patterns.json`: database DDL/DML, `rm -rf`, `dd if=`, `shred`, `systemctl stop|disable|restart|kill`, `kill -9`, `killall`, `pkill -f`, and the HDD6 archive paths. The hook also blocks the Docker and Colima commands when they are wrapped in `sh -c` or called by a full path.
- **Reads of archive data** are not blocked by the hook.
- **Outside this repo** (project and user instructions):
  - `docker system prune --volumes` is forbidden: volumes of stopped stacks hold real data.
  - Any destructive action goes through `action-guard.sh` (`/Volumes/logousb/SSD/Projects/action-guard.sh`), with a stated impact and rollback.
  - Immich is never stopped, deleted or pruned by an agent.
- **Scheduled scripts** (cron, `scriptslogo/`) run outside Claude Code and are not affected by these rules.

### Disks HDD6 and HDD12

The same layout applies to each disk. Paths use the absolute `//Volumes/...` form (see step 4).

| Folder | Read | Edit |
|---|---|---|
| `01-Froide` | allowed | denied |
| `02-Chaude` (Immich live data) | allowed | denied |
| `03-Travail-Actif/automatisation/` | allowed | allowed in subfolders; files directly inside denied |
| `03-Travail-Actif/administratif-entreprise/` | allowed | allowed in subfolders; files directly inside denied |
| `03-Travail-Actif`, other paths | allowed | no rule: Claude Code's auto mode decides |
| `04-Scratch` | allowed | allowed |
| Rest of the disk | allowed | no rule: Claude Code's auto mode decides |

Immich data in `02-Chaude` is never deleted or moved. Reads are allowed by decision on 2026-10-15.

### Hook behaviour

- A blocked call is appended to `incidents/log.jsonl`. Allowed calls are not logged. The file is local and gitignored.
- **False positives**: the match is a substring of the whole command, including quoted text and commit messages. On 2026-10-15 a commit message containing `docker rm` and `colima stop` was blocked.
- **Workaround for text only**: write the message to a file with the Write tool and run `git commit -F <file>`. Do not use this to get around a real destructive command.

## Installation

The deny rules, hook and disk rules live in `~/.claude/settings.json`, outside this repo.

### 1. Clone the repository

```bash
mkdir -p ~/Projects && cd ~/Projects
git clone https://github.com/loicgo29/agent-safety-guardrails
chmod +x agent-safety-guardrails/hooks/pre-execution-guard.sh
```

Keep the clone outside `~/.claude`.

### 2. Back up the settings

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
```

### 3. Add the deny rules

Add these entries to the existing `permissions.deny` array. Do not replace the array.

```json
{
  "permissions": {
    "deny": [
      "Bash(docker volume rm:*)",
      "Bash(docker volume prune:*)",
      "Bash(docker system prune:*)",
      "Bash(docker compose down:*)",
      "Bash(docker-compose down:*)",
      "Bash(docker rm:*)",
      "Bash(docker rmi:*)",
      "Bash(docker stop:*)",
      "Bash(docker kill:*)",
      "Bash(colima delete:*)",
      "Bash(colima stop:*)"
    ]
  }
}
```

The `:*` suffix matches the command and any arguments after it. `Bash(docker rm:*)` does not match `/usr/local/bin/docker rm` or `sh -c 'docker rm x'`; the hook covers those.

### 4. Add the disk rules (if you use the same layout)

A path in `~/.claude/settings.json` that begins with a single `/` is relative to `~/.claude/`, so `Read(/Volumes/HDD6/**)` has no effect. For an absolute path, use two slashes: `Read(//Volumes/HDD6/**)`.

Add to `permissions.allow`:

```json
"Read(//Volumes/HDD6/**)",
"Read(//Volumes/HDD12/**)",
"Edit(//Volumes/HDD6/04-Scratch/**)",
"Edit(//Volumes/HDD12/04-Scratch/**)",
"Edit(//Volumes/HDD6/03-Travail-Actif/automatisation/**/*)",
"Edit(//Volumes/HDD6/03-Travail-Actif/administratif-entreprise/**/*)",
"Edit(//Volumes/HDD12/03-Travail-Actif/automatisation/**/*)",
"Edit(//Volumes/HDD12/03-Travail-Actif/administratif-entreprise/**/*)"
```

Add to `permissions.deny`:

```json
"Edit(//Volumes/HDD6/01-Froide/**)",
"Edit(//Volumes/HDD6/02-Chaude/**)",
"Edit(//Volumes/HDD6/03-Travail-Actif/automatisation/*)",
"Edit(//Volumes/HDD6/03-Travail-Actif/administratif-entreprise/*)",
"Edit(//Volumes/HDD12/01-Froide/**)",
"Edit(//Volumes/HDD12/02-Chaude/**)",
"Edit(//Volumes/HDD12/03-Travail-Actif/automatisation/*)",
"Edit(//Volumes/HDD12/03-Travail-Actif/administratif-entreprise/*)"
```

Do not add a `Read` deny on `01-Froide` or `02-Chaude`: reading them is allowed by decision.

### 5. Add the PreToolUse hook

Add a `PreToolUse` entry next to the existing `hooks` block. Keep the other hook events (such as `SessionStart`).

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/absolute/path/to/agent-safety-guardrails/hooks/pre-execution-guard.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

Hook contract:

- Input: JSON on stdin. The command is in `tool_input.command`.
- Exit `0`: allowed. Exit `2`: blocked, and the message on stderr is shown to the model.
- The hook never prompts.
- Requires `jq` (`brew install jq`). Without it, the hook blocks every Bash call.

### 6. Validate the JSON

```bash
jq . ~/.claude/settings.json >/dev/null && echo "JSON valide"
```

### 7. Test

```bash
bash tests/agent-safety-tests.sh
```

The suite runs against a copy of the hook and rules, so the incidents log is not touched. Expected: `10 passed, 0 failed`.

Then start a new Claude Code session, since a session already open may not have the new settings. Check:

- Ask Claude to run `docker volume rm test-volume`: it must be refused, and `docker ps` must still run.
- Ask Claude to edit a non-existent file under `/Volumes/HDD6/02-Chaude/`: it must be refused.

Do not create or modify real files to test this.

## Optional: container auto-heal (not deployed)

Not deployed (decision of 2026-10-15). Kept for reference.

Docker healthchecks only report state. `willfarrell/autoheal` restarts containers whose healthcheck is `unhealthy`. It does not restart stopped containers.

```yaml
services:
  autoheal:
    image: willfarrell/autoheal:<pinned-version>
    restart: always
    environment:
      AUTOHEAL_CONTAINER_LABEL: autoheal
      AUTOHEAL_INTERVAL: 30
      AUTOHEAL_START_PERIOD: 120
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
```

Label only the services that may be restarted:

```yaml
  app:
    labels:
      - autoheal=true
```

- The Docker socket gives the autoheal container control over every container on the host. Treat it as a privileged component.
- A restart is a stop. Do not label services where an unplanned restart is unacceptable, such as a database during an import or a backup.
- Pin the image version. Check the socket path on your Docker runtime (Colima and Docker Desktop differ).

## Status (2026-10-15)

- **Deny rules and disk rules**: applied on the author's machine. Syntax checked against the Claude Code permissions documentation. Not yet verified in a live session.
- **Hook**: rewritten to the contract above. `tests/agent-safety-tests.sh` passes 10/10. Not yet verified inside a live session.
- **Auto-heal**: not deployed.
- **`CLAUDE_CODE_INTEGRATION.md`**: removed on 2026-10-15. This README replaces it.
- **`examples/`**: rewritten on 2026-10-15 to the current format. Copy the values, do not use it as-is.

## Open items

- DS124 mount path, to add its disk rules. The volume is not mounted when this was written.
- Live-session verification of the deny rules, the hook, and the first-level `Edit` deny on `automatisation/` and `administratif-entreprise/`.

## Files

```
agent-safety-guardrails/
├── README.md                        this file (single source of truth)
├── hooks/pre-execution-guard.sh     PreToolUse hook
├── rules/destructive-patterns.json  pattern groups read by the hook
├── incidents/log.jsonl              local log of blocked calls (gitignored)
├── examples/                        example settings
├── tests/agent-safety-tests.sh      hook test suite
└── scripts/                         empty
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Useful contributions: patterns from real incidents, and reports of bypasses (with a reproduction, not an exploit against third parties).

## License

MIT. See [LICENSE](LICENSE).

## Disclaimer

This is defense in depth, not a guarantee. Test it on your own setup and keep backups.
