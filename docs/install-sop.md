# SOP: Install the team pack

Use one path. On Claude and Grok, marketplace **or** the refresh script — not both — so skill names do not collide.

**Marketplace (Claude / Grok), from this repo:**

```bash
claude plugin marketplace add "$(pwd)"
claude plugin install multi-agentic-project-team@multi-agentic-project-team
grok plugin marketplace add "$(pwd)"
grok plugin install multi-agentic-project-team --trust
```

**Script (Gemini, agy, or every CLI on PATH):**

```bash
./scripts/refresh-team.sh
./scripts/refresh-team.sh --status
./scripts/refresh-team.sh --project /path/to/app
```

After the first script link, `/refresh-team` relinks. Never copy skills or agents by hand.

## `"$(pwd)"`

`"$(pwd)"` is the current working directory. Quote it so the path stays one argument.

The local folder and GitHub repo are both `multi-agentic-project-team` (hyphens, no spaces). Run the marketplace commands from that checkout root so `marketplace add` gets this repo’s path, not some other folder.
