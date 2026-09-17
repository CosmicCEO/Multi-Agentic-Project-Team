---
name: refresh-team
description: Install or refresh the Multi-Agentic Project Team skills and agents onto every AI CLI present on this machine (Claude, Grok, Gemini, Antigravity/agy). Use only when the user runs /refresh-team or explicitly asks to refresh/install/relink the team pack.
disable-model-invocation: true
user-invocable: true
argument-hint: "[--dry-run|--status|--project DIR|--only csv]"
---

# Refresh Team Pack

Run the installer. Do not reimplement linking in prose.

1. Resolve the repo root from this skill file (two directories up from `skills/refresh-team/`, or the path `refresh-team.sh` already knows).
2. Run, forwarding any user arguments:

```bash
"<repo>/scripts/refresh-team.sh" <args>
```

Default (no args) is a live refresh of user-global homes for every CLI on `PATH`.

3. Summarize the script output: which CLIs were missing, how many skills/agents linked, any `skipped` rows. The last line is `summary new=… ok=…`. `new` (live) and `--status` `would-link` are skills or agents in the repo that were not linked yet. Do not dump the full table unless the user asked for `--status` or verbose.
4. Do not copy files. Do not edit vendor YAML. Do not enable plugins or marketplaces.
