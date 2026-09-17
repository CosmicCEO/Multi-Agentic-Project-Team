# Multi-Agentic Project Team

Canonical skill/agent pack.

- Claude / Grok: `plugin marketplace add` this repo, then install `multi-agentic-project-team`.
- Gemini / agy, or all CLIs at once: `./scripts/refresh-team.sh` or `/refresh-team`.

- Skills: `skills/<name>/SKILL.md` (including `director-operating-model` — shared router both directors load)
- Agents: `agents/<name>.md` (directors only: `swift-project-director`, `swift-port-director`). Leaf workers `xcode-admin` / `xcode-implementer` / `xcode-quality-auditor` are skills. Spawn a general worker only when the operating model says to; otherwise load the skill in-session.
- Do not edit copies under `~/.claude`, `~/.grok`, or `~/.gemini` — those are symlinks.
