# Agent Safety Guardrails

Deterministic guardrails for Claude Code: destructive commands are refused by the runtime, not by the model's good intentions.

## Principle

A rule written in `CLAUDE.md` is text the model can ignore. The controls in this repo are executed by Claude Code itself:

| Layer | Mechanism | Who enforces it | Weakness |
|---|---|---|---|
| 1. Deny rules | `permissions.deny` in `~/.claude/settings.json` | Claude Code, before the tool runs | Bash rules match the command text: `sh -c '...'`, `/bin/rm`, or a different subcommand form are not matched |
| 2. PreToolUse hook | Script receives the command as JSON on stdin, exits `2` to block | Claude Code | Only as good as the script (see Status) |
| 3. `CLAUDE.md` | Instructions | The model | Not a control. Documentation only |

Deny rules are a guardrail, not a security boundary. Real protection for data comes from backups, from not mounting the Docker socket into containers, and from keeping destructive operations out of the agent's reach.

### What a Bash deny rule matches

Claude Code matches the command text it writes, after splitting compound commands (`&&`, `;`, `|`, ...) and stripping a fixed set of wrappers (`timeout`, `nice`, `nohup`, `xargs`, ...). Per the Claude Code permissions documentation:

| Rule | Matched | Not matched |
|---|---|---|
| `Bash(docker rm:*)` | `docker rm web` | `/usr/local/bin/docker rm web`, `sh -c 'docker rm web'` |
| `Bash(docker rm:*)` | `cd /tmp && docker rm web` (split, then matched) | |
| `Bash(docker rm:*)` | `FOO=bar docker rm web` (deny ignores leading assignments) | |
| `Bash(docker rm:*)` | `docker exec immich_server docker rm web` (`docker exec` is not a stripped wrapper, so the inner command is not checked) | |

Blocking the shell-wrapper and full-path forms is the job of the hook (step 4).

## Requirements

- Claude Code (current version, `claude --version`)
- `jq` (`brew install jq`)
- macOS or Linux, `bash`

## Installation

### 1. Clone the repository

```bash
mkdir -p ~/Projects && cd ~/Projects
git clone https://github.com/loicgo29/agent-safety-guardrails
chmod +x agent-safety-guardrails/hooks/pre-execution-guard.sh
```

Keep the clone outside `~/.claude`. Claude Code reads only the settings file from there.

### 2. Add the deny rules (works without the hook)

Open `~/.claude/settings.json` and add these entries to the existing `permissions.deny` array. Do not replace the array: keep the entries you already have.

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

The `:*` suffix matches the command and any arguments after it. `Bash(docker volume rm:*)` blocks `docker volume rm data` and `docker volume rm -f data`.

**Path rules in user settings.** A `/path` pattern in `~/.claude/settings.json` is relative to `~/.claude/`, not to the filesystem root. For an absolute path, use two slashes:

```json
"Read(//Volumes/HDD6/01-Froide/**)"
```

Not `Read(/Volumes/HDD6/01-Froide/**)`, which would match `~/.claude/Volumes/...`.

### 3. Verify the deny rules

Start a new Claude Code session and ask it to run:

```text
docker volume rm test-volume
```

Expected: the command is refused by the permission system and never executed. A harmless command such as `docker ps` must still run.

### 4. Add the PreToolUse hook

Add a `PreToolUse` entry next to the existing `hooks` block in `~/.claude/settings.json`. Use an absolute path. If the file already has other hook events (such as `SessionStart`), keep them.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/yourname/Projects/agent-safety-guardrails/hooks/pre-execution-guard.sh",
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
- The hook must never prompt for input. A prompt cannot be answered inside a hook.

### 5. Test the hook

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"docker volume rm test"}}' \
  | ~/Projects/agent-safety-guardrails/hooks/pre-execution-guard.sh
echo "exit=$?"   # expected: exit=2

echo '{"tool_name":"Bash","tool_input":{"command":"docker volume ls"}}' \
  | ~/Projects/agent-safety-guardrails/hooks/pre-execution-guard.sh
echo "exit=$?"   # expected: exit=0
```

## Policy: where each rule lives

- **`~/.claude/settings.json` → `permissions.deny`**: command prefixes refused before execution. Edit here to add or remove a rule.
- **`rules/destructive-patterns.json`**: pattern groups with severity and reason, read by the hook. Edit in the repo, then `git pull` on other machines.
- **`incidents/log.jsonl`**: one line per command blocked by the hook. Allowed commands are not logged. Review it to tune the patterns.

Patterns are plain text, matched as substrings of the whole command, case-insensitively. Keep them specific: a bare word such as `DROP` also matches `dropdown`, and a pattern also matches inside quoted text (`echo "docker rm"` is blocked).

## Optional: container auto-heal

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

Then label only the services that may be restarted:

```yaml
  app:
    labels:
      - autoheal=true
```

Warnings:

- The Docker socket gives the autoheal container control over every container on the host. Treat it as a privileged component.
- A restart is a stop. Do not label services where an unplanned restart is unacceptable, such as a database during an import or a backup.
- Pin the image version. Check the socket path on your Docker runtime (Colima and Docker Desktop differ).

## Status

- **Deny rules**: syntax checked against the Claude Code permissions documentation. Applied in the author's `~/.claude/settings.json`. Not yet tested end to end in a live session.
- **Hook**: rewritten to the contract above (reads JSON on stdin, exits `2` to block, never prompts). Tested with simulated JSON inputs (9 cases: blocked and allowed commands, invalid JSON, empty command). Not yet tested inside a live Claude Code session.
- **Hook limits**: it matches the pattern list in `rules/destructive-patterns.json`, not the intent of the command. `docker compose -f file.yml down` is not matched by the hook's `docker compose down` pattern, nor by the deny rule `Bash(docker compose down:*)`, which matches the prefix only. Add a pattern for `down` with a file flag if that form is used. Commands that build a destructive call indirectly (variables, scripts, `eval`) are not detected.
- **Hook dependency**: requires `jq`. Without it, the hook blocks every Bash call (fail-closed).
- **`CLAUDE_CODE_INTEGRATION.md`**: outdated (it describes a `before-bash` key that Claude Code does not read, and a confirmation prompt instead of a block). Superseded by this README.
- **`scripts/`**: empty. `PLAN.md` is the historical design, not the install procedure.

## Files

```
agent-safety-guardrails/
├── README.md
├── hooks/pre-execution-guard.sh     PreToolUse hook (step 4)
├── rules/destructive-patterns.json  pattern groups read by the hook
├── rules/memory-requirements.md     rules for the agent
├── incidents/log.jsonl              audit trail
├── examples/                        example settings and patterns
└── tests/agent-safety-tests.sh
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Useful contributions: patterns from real incidents, and reports of bypasses (with a reproduction, not an exploit against third parties).

## License

MIT. See [LICENSE](LICENSE).

## Disclaimer

This is defense in depth, not a guarantee. Test it on your own setup and keep backups.
