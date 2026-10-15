# Agent Safety Guardrails

Deterministic guardrails for Claude Code: destructive commands are refused by Claude Code itself, not by the model's good intentions.

Last updated: 2026-10-15. The decisions below are the ones applied on the author's machine.

## Principle

A rule written in `CLAUDE.md` is text the model can ignore. The controls in this repo are executed by Claude Code:

| Layer | Mechanism | Who enforces it | Weakness |
|---|---|---|---|
| 1. Deny rules | `permissions.deny` in `~/.claude/settings.json` | Claude Code, before the tool runs | Bash rules match the command text: `sh -c '...'`, `/bin/rm`, or another form are not matched |
| 2. PreToolUse hook | Script receives the command as JSON on stdin, exits `2` to block | Claude Code | Substring matching: blocks some harmless text too (see Hook) |
| 3. `CLAUDE.md` | Instructions | The model | Not a control. Documentation only |

Deny rules and the hook are guardrails, not a security boundary. Real protection for data comes from backups, from not mounting the Docker socket into containers, and from keeping destructive operations out of the agent's reach.

## Current policy

### Destructive commands

Refused by deny rules (`permissions.deny`):

- `rm`, `rm -r`, `rm -rf`, `find` (from the original settings)
- `docker volume rm`, `docker volume prune`, `docker system prune`
- `docker compose down`, `docker-compose down`
- `docker rm`, `docker rmi`, `docker stop`, `docker kill`
- `colima delete`, `colima stop`

Refused by the PreToolUse hook, from the groups in `rules/destructive-patterns.json`:

- Database: `DROP`, `DELETE FROM`, `TRUNCATE`, `ALTER TABLE`, `GRANT`, `REVOKE`
- Filesystem: `rm -rf`, `rm -f`, `dd if=`, `shred`, `mv /live`, `mv /critical`
- Containers: the Docker and Colima commands listed above, including through `sh -c` or a full path
- Services: `systemctl stop|disable|restart|kill`
- Processes: `kill -9`, `killall`, `pkill -f`
- Live archive: `rm -rf /Volumes/HDD6`, `mv /Volumes/HDD6/02-Chaude/immich`, `DROP SCHEMA immich`, `DELETE FROM asset`

Reads of archive data are not blocked by the hook.

Rules kept outside this repo, from the project and user instructions:

- `docker system prune --volumes` is forbidden: volumes of stopped stacks hold real data (`CLAUDE.md` of the ecosystem).
- Any destructive action goes through `action-guard.sh` (`/Volumes/logousb/SSD/Projects/action-guard.sh`), with a stated impact and rollback.
- Immich is never stopped, deleted or pruned by an agent.

### Disks HDD6 and HDD12

The same layout applies to each disk. Rules use the absolute `//Volumes/...` form.

| Folder | Read | Edit |
|---|---|---|
| `01-Froide` | allowed | denied |
| `02-Chaude` (Immich live data) | allowed | denied |
| `03-Travail-Actif/automatisation/` | allowed | allowed in subfolders; files directly inside are denied |
| `03-Travail-Actif/administratif-entreprise/` | allowed | allowed in subfolders; files directly inside are denied |
| `03-Travail-Actif`, other paths | allowed | no rule: decided by Claude Code's auto mode |
| `04-Scratch` | allowed | allowed |
| Rest of the disk | allowed (`Read(//Volumes/HDD6/**)`) | no rule: decided by Claude Code's auto mode |

- Immich data in `02-Chaude` is never deleted or moved. Reads are allowed by decision on 2026-10-15.
- The "files directly inside are denied" rule relies on the `*` / `**/*` interaction between two rules. It is to be checked in a live session (see Status).
- **DS124**: not mounted when this was written. Its mount path is not yet recorded, so no rule exists for it.

### Hook

- On the author's machine: `/Volumes/logousb/SSD/Projects/agent-safety-guardrails/hooks/pre-execution-guard.sh`.
- A blocked call is appended to `incidents/log.jsonl`. Allowed calls are not logged. The file is local and gitignored.
- **False positives**: the match is a substring of the whole command, including quoted text and commit messages. On 2026-10-15 a commit message containing `docker rm` and `colima stop` was blocked.
- **Workaround for text only**: write the message to a file with the Write tool and run `git commit -F <file>`. Do not use this to get around a real destructive command.

### Container auto-heal

Not deployed (decision of 2026-10-15). The section below is kept for reference only.

## Installation

The deny rules, hook and disk rules live in `~/.claude/settings.json`, outside this repo. Steps:

### 1. Clone the repository

```bash
mkdir -p ~/Projects && cd ~/Projects
git clone https://github.com/loicgo29/agent-safety-guardrails
chmod +x agent-safety-guardrails/hooks/pre-execution-guard.sh
```

Keep the clone outside `~/.claude`. Claude Code reads only the settings file from there.

### 2. Back up the settings

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
```

### 3. Add the deny rules

Add these entries to the existing `permissions.deny` array. Do not replace the array: keep the entries already there.

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

The `:*` suffix matches the command and any arguments after it. A deny on `Bash(docker rm:*)` does not match `/usr/local/bin/docker rm` or `sh -c 'docker rm x'`; the hook covers those.

### 4. Add the disk rules (if you use the same layout)

Paths in `~/.claude/settings.json` that begin with a single `/` are relative to `~/.claude/`. For an absolute path, use two slashes:

```json
"Read(//Volumes/HDD6/**)"
```

Not `Read(/Volumes/HDD6/**)`, which would match `~/.claude/Volumes/...` and have no effect.

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
- The hook never prompts. A prompt cannot be answered inside a hook.
- Requires `jq` (`brew install jq`). Without it, the hook blocks every Bash call.

### 6. Validate the JSON

```bash
jq . ~/.claude/settings.json >/dev/null && echo "JSON valide"
```

### 7. Test

Run the test suite. It uses a copy of the hook and rules, so the incidents log is not touched:

```bash
bash tests/agent-safety-tests.sh
```

Expected: `10 passed, 0 failed`.

Then start a new Claude Code session, since a session already open may not have the new settings. In that session, check:

- Ask Claude to run `docker volume rm test-volume`: it must be refused, and `docker ps` must still run.
- Ask Claude to edit a non-existent file under `/Volumes/HDD6/02-Chaude/`: it must be refused.

Do not create or modify real files to test this.

## Policy: where each rule lives

- **`~/.claude/settings.json`**: deny, allow and hook rules for this machine. Not in the repo. Follow the installation steps to change them.
- **`rules/destructive-patterns.json`**: pattern groups with severity and reason, read by the hook. Edit in the repo, then `git pull` on other machines.
- **`incidents/log.jsonl`**: local log of blocked calls. Review it to tune the patterns. Gitignored.

Patterns are plain text, matched case-insensitively as substrings. Keep them specific: `DROP` also matches `dropdown`.

Scheduled scripts (cron, `scriptslogo/`) run outside Claude Code and are not affected by these rules.

## Optional: container auto-heal (not deployed)

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

Warnings:

- The Docker socket gives the autoheal container control over every container on the host. Treat it as a privileged component.
- A restart is a stop. Do not label services where an unplanned restart is unacceptable, such as a database during an import or a backup.
- Pin the image version. Check the socket path on your Docker runtime (Colima and Docker Desktop differ).

## Status (2026-10-15)

- **Deny rules**: applied on the author's machine. Syntax checked against the Claude Code permissions documentation. Not yet verified in a live session.
- **Hook**: rewritten to the contract above. `tests/agent-safety-tests.sh` passes 10/10. Not yet verified inside a live session.
- **Disk rules**: converted to `//` paths on 2026-10-15. Reads of `01-Froide` and `02-Chaude` allowed by decision. The first-level `Edit` deny on `automatisation/` and `administratif-entreprise/` is to be checked in a live session.
- **Auto-heal**: not deployed.
- **`CLAUDE_CODE_INTEGRATION.md`**: removed on 2026-10-15. This README replaces it.
- **`examples/`**: rewritten on 2026-10-15 to the current format. Copy the values, do not use it as-is.

## Open items

- DS124 mount path, to add its disk rules.
- Live-session verification of the deny rules, the hook, and the first-level `Edit` deny.

## Files

```
agent-safety-guardrails/
├── README.md
├── hooks/pre-execution-guard.sh     PreToolUse hook
├── rules/destructive-patterns.json  pattern groups read by the hook
├── rules/memory-requirements.md     rules for the agent
├── incidents/log.jsonl              local log of blocked calls (gitignored)
├── examples/                        example settings and patterns
├── tests/agent-safety-tests.sh      hook test suite
├── scripts/                         empty
└── PLAN.md                          historical design, not the install procedure
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Useful contributions: patterns from real incidents, and reports of bypasses (with a reproduction, not an exploit against third parties).

## License

MIT. See [LICENSE](LICENSE).

## Disclaimer

This is defense in depth, not a guarantee. Test it on your own setup and keep backups.
