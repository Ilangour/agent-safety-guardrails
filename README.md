# Agent Safety Guardrails

**Prevent LLM agents from launching destructive actions without explicit human approval.**

A production-ready framework for securing autonomous agents against accidental (or malicious) destructive operations.

## Problem

LLM agents with tool access can launch dangerous commands:
- `DROP SCHEMA` on production databases
- `rm -rf /critical/data/`
- `docker compose down` on running services
- Without asking for confirmation

**Root cause:** Text-based safety rules ("don't do X") are not enforced. Agents bypass them via objective reformulation, autonomy mindset, or complexity.

**This repo:** Multi-layer defense architecture proven in research (SafeMCP, ToolSafe, Constitutional AI).

## Solution Architecture

```
┌─────────────────────────────────────────┐
│   3-Phase Implementation                │
├─────────────────────────────────────────┤
│ Phase 1: Memory + Whitelist (4h)        │
│  └─ Memory-augmented decision-making    │
│  └─ Tool whitelist with confirmation    │
│                                         │
│ Phase 2: Deterministic Blocker (4h)     │
│  └─ Pre-execution hook intercepts       │
│  └─ Pattern matching vs destructive DB  │
│                                         │
│ Phase 3: Validation + Sandbox (4h)      │
│  └─ Test suite ensures blocking works   │
│  └─ Container sandbox (optional)        │
└─────────────────────────────────────────┘
```

## Quick Start

```bash
# Clone this repo
git clone https://github.com/logo-solutions/agent-safety-guardrails
cd agent-safety-guardrails

# Read the complete plan
cat PLAN.md

# Execute Phase 1 (Memory + Whitelist)
./scripts/01-setup-safety-dirs.sh
./scripts/02-init-destructive-patterns.sh
./scripts/03-init-memory-requirements.sh
./scripts/04-configure-whitelist.sh

# Execute Phase 2 (Blocker)
./scripts/05-deploy-blocker.sh
./scripts/06-integrate-hook.sh

# Execute Phase 3 (Tests)
./scripts/07-run-tests.sh
./scripts/08-review-incidents.sh
```

## Key Concepts

### 1. Memory-Driven Decision Making
Agents MUST consult safety memory before every destructive action. Consultation is forced via context window, not optional.

```json
{
  "memory-requirement": "Before DROP, DELETE, rm -rf → READ destructive-patterns.json",
  "enforcement": "Mandatory context injection"
}
```

### 2. Destructive Patterns Whitelist
Define patterns that trigger confirmation. Not blacklist (too easy to bypass), whitelist (explicit approval).

```json
{
  "patterns": [
    "DROP SCHEMA",
    "rm -rf /Volumes/HDD6",
    "docker compose down"
  ],
  "severity": "CRITICAL",
  "action": "Block + require explicit confirmation"
}
```

### 3. Pre-Execution Hook
Before any bash command runs, scan for patterns. If match → require human confirmation.

```bash
if command matches destructive-patterns.json:
  → BLOCK
  → Require: "CONFIRM DESTRUCTIVE"
  → User must type exact string
  → Log incident
else:
  → ALLOW
```

## Files & Structure

```
agent-safety-guardrails/
├── README.md (this file)
├── PLAN.md (complete 3-phase implementation plan)
├── LICENSE (MIT)
├── CONTRIBUTING.md (how to contribute)
│
├── scripts/
│   ├── 01-setup-safety-dirs.sh
│   ├── 02-init-destructive-patterns.sh
│   ├── 03-init-memory-requirements.sh
│   ├── 04-configure-whitelist.sh
│   ├── 05-deploy-blocker.sh
│   ├── 06-integrate-hook.sh
│   ├── 07-run-tests.sh
│   ├── 08-review-incidents.sh
│   └── 09-build-sandbox.sh
│
├── rules/
│   ├── destructive-patterns.json (patterns to block)
│   └── memory-requirements.md (what agent must check)
│
├── hooks/
│   └── pre-execution-guard.sh (the blocker)
│
├── tests/
│   └── agent-safety-tests.sh
│
└── examples/
    ├── settings.json.example
    ├── destructive-patterns.json.example
    └── incidents-log.jsonl.example
```

## Integration Points

### For Claude Code
Update `~/.claude/settings.json`:
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

### For Other Agents (LangChain, AutoGPT, etc.)
Wrap your tool invocation:
```python
from agent_safety import PreExecutionGuard

guard = PreExecutionGuard(
  patterns_file="./rules/destructive-patterns.json",
  require_confirmation=True
)

# Before tool execution:
if not guard.check(command):
    raise BlockedActionError(f"Destructive pattern detected: {command}")
```

## Research Foundation

This framework is based on peer-reviewed research:

- **SafeMCP** — Proactive power regulation (arxiv:2606.01991)
- **ToolSafe** — Enhanced tool invocation safety (arxiv:2601.10156)
- **Constitutional AI** — Hard constraints via training (Anthropic)
- **Memory-Driven Agents** — Forced consultation (arxiv:2509.26340)
- **Deterministic Pre-Action Authorization** (arxiv:2603.20953)

See [PLAN.md](PLAN.md) for full references.

## Why This Works

| Approach | Limit | This Framework |
|----------|-------|---|
| Text prompts ("don't do X") | Bypassable via reformulation | ✅ Deterministic blocker |
| JSON blacklist | Incomplete, model finds workarounds | ✅ Whitelist + confirmation |
| Passive memory | Agent can ignore | ✅ Forced memory consultation |
| Single gate | One failure = breach | ✅ Multi-layer defense |

## Incident Logging

Every blocked action is logged:

```json
{
  "timestamp": "2026-10-15T21:45:32+02:00",
  "command": "DROP SCHEMA public CASCADE",
  "status": "BLOCKED",
  "pattern_matched": "Database-Operations",
  "severity": "CRITICAL"
}
```

Review incidents and update patterns accordingly.

## Success Criteria

After Phase 3:
- ✅ No agent can launch destructive commands unilaterally
- ✅ All dangerous operations require explicit human confirmation
- ✅ Every action is logged with full audit trail
- ✅ Patterns are updateable without redeploying agent
- ✅ Zero-trust model: verify before every execution

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

We welcome:
- Additional destructive patterns (share your incidents)
- Integration examples (Claude, LangChain, AutoGPT, etc.)
- Hardening feedback (security researchers)
- Translations of documentation

## License

MIT License. See [LICENSE](LICENSE).

## Security Disclaimer

This framework is a **defense-in-depth approach**, not a guarantee. Security is a practice, not a product.

- Test thoroughly before production use
- Keep destructive-patterns.json updated
- Monitor incident logs regularly
- Never skip the multi-layer checks

## Maintainers

Created by [logo-solutions](https://github.com/logo-solutions) as a result of incident analysis and research into LLM agent safety.

## Citation

If you use this framework, cite as:

```bibtex
@software{agent-safety-guardrails-2026,
  title={Agent Safety Guardrails: Multi-Layer Defense for LLM Agents},
  author={logo-solutions},
  year={2026},
  url={https://github.com/logo-solutions/agent-safety-guardrails}
}
```

---

**Status:** Production-ready for Phase 1-2. Phase 3 (sandbox) is optional/advanced.

**Last Updated:** 2026-10-15

**Questions?** Open an issue or see [CONTRIBUTING.md](CONTRIBUTING.md).
