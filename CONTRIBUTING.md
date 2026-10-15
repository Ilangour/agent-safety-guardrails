# Contributing to Agent Safety Guardrails

## How to Contribute

### 1. Report Security Incidents
Found a new destructive pattern? Open an issue with:
- Pattern detected (e.g., `systemctl stop service`)
- Impact (what could go wrong)
- Suggested mitigation

Example:
```
Title: Add systemctl pattern to blocker
Description: Agents can stop system services. Add to destructive-patterns.json:
{
  "name": "systemd-control",
  "patterns": ["systemctl stop", "systemctl restart"]
}
```

### 2. Propose Integration Examples
Show how to use this framework with:
- LangChain
- AutoGPT
- CrewAI
- Other agents

Add the example under `examples/` and link it from the README.

### 3. Improve Documentation
- Translate README to other languages
- Clarify confusing sections
- Add diagrams or examples

### 4. Harden the Blocker
Found a bypass? Report privately in security issue (don't publicly disclose).

We use a responsible disclosure process.

## Code of Conduct

- Be respectful
- No spamming or self-promotion
- Focus on safety, not surveillance

## License

By contributing, you agree your work is MIT licensed.

---

Questions? Open an issue.
