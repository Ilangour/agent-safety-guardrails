# Agent Safety Guardrails

Deterministic guardrails for Claude Code: destructive commands are refused by Claude Code itself, not by the model's good intentions.

Last updated: 2026-10-15. The decisions below are the ones applied on the author's machine.

## Principle

A rule written in `CLAUDE.md` is text the model can ignore. The controls in this repo are executed by Claude Code:

| Layer | Mechanism | Weakness |
|---|---|---|
| 1. Deny rules | `permissions.deny` in `~/.claude/settings.json` | Bash rules match the command text: `sh -c '...'` or `/bin/rm` are not matched |
| 2. PreToolUse hook | `hooks/guard.sh`: [cc-safety-net](https://github.com/kenryu42/cc-safety-net) (MIT, pinned, strict mode) parses the command, then `rules/destructive-patterns.json` is applied as a local overlay | The overlay is substring matching: also blocks harmless text (see Hook). The engine is static analysis, not a sandbox |
| 3. `CLAUDE.md` | Instructions | Not a control |

Deny rules and the hook are a seat belt against honest mistakes, not a security boundary: combine them with a sandbox and least privilege (read-only DB role, user outside the `docker` group, backups). Real protection for data comes from backups, from not mounting the Docker socket into containers, and from keeping destructive operations out of the agent's reach.

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

`hooks/guard.sh` stacks three layers; each one can only tighten the decision (`deny` > `ask` > `allow`):

1. **cc-safety-net** (`npx -y cc-safety-net@2.6.12 hook --coding-cli`, `CC_SAFETY_NET_LEVEL=strict`): shell-aware parser. Catches `rm -r -f`, `/bin/rm`, `sudo rm`, `bash -c "rm …"`, `$(echo rm) -rf /`, `r''m -rf /`, `rm$IFS-rf$IFS/`, `base64 -d | sh`, `find / -delete`, `git push --force`, `git reset --hard`, `git clean -fd`; denies what it cannot parse. Set `CC_SAFETY_NET_LEVEL=paranoid` to also deny `rm -rf ./x` inside the project.
2. **`hooks/pre-execution-guard.sh`** with `rules/destructive-patterns.json`, unchanged: Docker, Colima, database DDL, archive paths.
3. **Ask overlay**: `terraform destroy|apply`, `lxc delete|restore` return `permissionDecision: "ask"`, which forces Claude Code's native prompt (also in auto mode).

If `node`/`npx` is missing the engine cannot run: the hook then returns `ask` for any command containing a sensitive keyword (`rm`, `git push`, `drop`, `sudo`, `sh`, …) and still applies layer 2. It never allows silently.

- Every decision is appended as one JSON line (built with `jq --arg`, not string concatenation) to `${XDG_STATE_HOME:-~/.local/state}/agent-safety-guardrails/decisions.jsonl`, override with `GUARD_LOG`. Layer 2 keeps writing blocked calls to `incidents/log.jsonl` (local, gitignored).
- **False positives**: the match is a substring of the whole command, including quoted text and commit messages. On 2026-10-15 a commit message containing `docker rm` and `colima stop` was blocked.
- **Workaround for text only**: write the message to a file with the Write tool and run `git commit -F <file>`. Do not use this to get around a real destructive command.

## Installation

The deny rules, hook and disk rules live in `~/.claude/settings.json`, outside this repo.

### 1. Clone the repository

```bash
mkdir -p ~/Projects && cd ~/Projects
git clone https://github.com/loicgo29/agent-safety-guardrails
chmod +x agent-safety-guardrails/hooks/*.sh
```

Keep the clone outside `~/.claude`. The hook needs `jq` and Node.js 18+ (`node`, `npx`): the first call downloads `cc-safety-net@2.6.12` into the npx cache (about 1 s afterwards). To avoid npx at runtime: `npm install -g cc-safety-net@2.6.12`.

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
            "command": "/absolute/path/to/agent-safety-guardrails/hooks/guard.sh",
            "timeout": 30,
            "onFailure": "block"
          }
        ]
      }
    ]
  }
}
```

Hook contract:

- Input: JSON on stdin. The command is in `tool_input.command`.
- Exit `0` with empty stdout: allowed. Exit `2`: blocked, and the message on stderr is shown to the model. Exit `0` with `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask",...}}`: Claude Code shows its native confirmation prompt (denied in `-p` mode, where nobody can answer).
- The hook never reads a TTY.
- `onFailure: "block"` (Claude Code 2.1.295+) blocks the call if the hook crashes, times out or prints invalid output; the default is to let the command run.
- Requires `jq` (`brew install jq`). Without it, the hook blocks every Bash call.

### 6. Validate the JSON

```bash
jq . ~/.claude/settings.json >/dev/null && echo "JSON valide"
```

### 7. Test

```bash
bash tests/agent-safety-tests.sh      # layer 2 alone, expected: 10 passed, 0 failed
npx -y bats@1.13.0 tests/guard.bats   # full hook, expected: 9 tests, 0 failures, 2 skipped
```

Both suites run against a copy of the hooks and rules, so the incidents log is not touched. `tests/guard.bats` feeds each line of `tests/corpus/*.txt` as a real PreToolUse JSON: `must_block.txt`, `must_ask.txt`, `must_allow.txt`, plus `known_gaps.txt` (dangerous commands still allowed) and `false_positives.txt` (harmless commands still blocked by the overlay). The two last files are reported as skips, not hidden: move a line out of them when the behaviour changes. The same suites run in GitHub Actions on every push and pull request (`.github/workflows/test.yml`).

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
- **Hook**: `hooks/guard.sh` delegates to cc-safety-net 2.6.12 (strict) and keeps `pre-execution-guard.sh` as overlay. `tests/agent-safety-tests.sh` 10/10, `tests/guard.bats` 9/9. Verified in a live `claude -p` session on a throwaway folder: both `rm -rf` calls blocked, log written.
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
├── hooks/guard.sh                   PreToolUse hook: cc-safety-net + overlay + ask rules
├── hooks/pre-execution-guard.sh     overlay (this repo's own patterns), also usable alone
├── rules/destructive-patterns.json  pattern groups read by the overlay
├── incidents/log.jsonl              local log of overlay blocks (gitignored)
├── examples/                        example settings
├── tests/agent-safety-tests.sh      overlay test suite
├── tests/guard.bats, tests/corpus/  full hook test suite (bats) and command corpora
└── .github/workflows/test.yml       CI: both suites on push and pull request
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Useful contributions: patterns from real incidents, and reports of bypasses (with a reproduction, not an exploit against third parties).

## License

MIT. See [LICENSE](LICENSE).

## Disclaimer

This is defense in depth, not a guarantee. Test it on your own setup and keep backups.
