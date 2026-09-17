# Multi-Agentic Project Team

## Abstract

This repo is a single source of truth for a cross-project, cross-harness AI workflow. It is
installed once (marketplace or symlink) and then used identically across Claude Code, Grok
Build, Gemini CLI, and Antigravity (`agy`) on every project, instead of each harness or project
maintaining its own copy of process knowledge.

It provides two independent, separable things:

1. **A cross-harness daily workflow (`harness-routing`).** You pick one exact trigger phrase
   (e.g. `<YOUR TRIGGER PHRASE>`) and say it to Gemini every session. Gemini reads the active
   project's `docs/STATUS.md`, decides what's next, and dispatches execution to Claude or
   bookkeeping to Grok in non-interactive/headless mode. Each dispatched harness appends its
   result to `docs/STATUS.md`; Gemini reports back on the next trigger. This is the default,
   lean way of working and needs none of the role-split machinery below.
2. **An opt-in director + role-split pack** (`swift-project-director` / `swift-port-director`
   plus `xcode-admin` / `xcode-implementer` / `xcode-quality-auditor`) for projects that
   specifically want a Planner/Implementer/Parity/Admin-style workflow. **Not every project
   wants this** — some projects' own `AGENTS.md` explicitly bans the split (see "Director
   scoping" below). Check the target project's standing constraints before using it; the daily
   loop above works fine without it.

---

## Details

### Layout

- `agents/` — real Claude Code Agent definitions (`*.md` with model/tools frontmatter).
- `skills/` — Skill definitions (`<name>/SKILL.md`), flat one level deep.
- `scripts/refresh-team.sh` — idempotent symlink installer (see "Install" below).

### Install

Clone (folder name matches GitHub, no spaces), then pick one path — **marketplace or
`refresh-team.sh`, not both**, to avoid skill-name collisions:

```bash
git clone https://github.com/<your-org>/multi-agentic-project-team.git
cd multi-agentic-project-team
```

Claude Code and Grok Build share a plugin marketplace (`.claude-plugin/marketplace.json`; Grok
reads that layout):

```bash
# Claude
claude plugin marketplace add "$(pwd)"
claude plugin install multi-agentic-project-team@multi-agentic-project-team

# Grok
grok plugin marketplace add "$(pwd)"
grok plugin install multi-agentic-project-team --trust
```

Gemini CLI and Antigravity (`agy`) do not use that marketplace. For those hosts, or to refresh
every CLI on `PATH` at once (symlinks into `~/.claude/skills`, `~/.grok/skills`,
`~/.gemini/skills`, `~/.gemini/config/skills`, and the Antigravity/`agy` equivalents):

```bash
./scripts/refresh-team.sh
./scripts/refresh-team.sh --status
./scripts/refresh-team.sh --project /path/to/swift-app   # optional per-repo links
```

After a script install, `/refresh-team` works in any linked CLI. Do not copy files by hand —
edit the source under this repo; the CLI-side copies are symlinks.

### The daily loop (`harness-routing`)

The default way this whole pack gets used day to day. Full detail lives in
`skills/harness-routing/SKILL.md`; summary:

- **Trigger:** one exact phrase you choose (e.g. `<YOUR TRIGGER PHRASE>`), said to Gemini — a
  bare "good morning" greeting is *not* the trigger and gets a plain reply, so casual
  conversation never accidentally kicks off dispatch.
- **Decision-making is Gemini's role only.** Since the skill is symlinked identically into all
  three harnesses, Claude or Grok can technically recognize the trigger too, but they report
  status only and defer the "what's next" call to Gemini — this avoids two harnesses each
  running the full decision loop and producing different, unreconciled task menus.
- **Allocation model:** Gemini = large-context ingestion and the daily decision role; Claude =
  implementation with tool access (the real edit/build/test loop); Grok = fast, cheap
  bookkeeping (issue triage, board/status updates) — never a substitute implementer.
- **Handoff state:** one shared `docs/STATUS.md` per project. Every harness reads it before
  acting and appends a dated entry when done — never rewrites existing entries.
- **Stall handling:** every headless dispatch runs under a wall-clock `timeout`. On a stall
  (timeout or a quota/limit error), the dispatcher checks actual branch state (`git status`,
  `git diff --stat`) before doing anything else, and retries with a narrower dispatch on the
  *same* harness rather than handing the interrupted implementation to a different one. The
  stall itself gets logged in `docs/STATUS.md` so the next loop surfaces it.
- **Human checkpoint:** step 1 (the trigger) stays human-initiated, not cron-scheduled. Dispatch
  is automated *execution*, not an unattended pipeline — each harness still asks before
  push/destructive actions unless you have explicitly granted a scoped autonomous session.

### Directors (opt-in role split; Agents, not Skills)

- **`swift-project-director`** — directs new or existing Swift/macOS/iOS development
  (greenfield design or brownfield feature work, not porting) using a PDCA plan/build/check/
  document cycle.
- **`swift-port-director`** — directs C/C++-to-Swift porting projects, preserving functional
  parity, using the same PDCA cycle plus a mandatory parity-audit gate before any component is
  marked done.

Both directors act as their own Planner (sequencing, decisions log, rulings on open questions)
rather than delegating that role out. They load **`director-operating-model`** and route each
unit of work to the cheapest correct tool (in-session skill, `explore`, spawned
`general-purpose` + role skill, Quality Auditor, `/review`, Xcode MCP). Spawn only for a fresh
context window, a worktree-isolated writer, or an adversarial audit — not for every
Admin/Implementer pass. Small, non-architectural items stay in-session (light-track) rather than
the full pre-brief → spawn → report → ruling → audit pipeline.

These two live in `agents/` (not as Skill directories) because Skill frontmatter can't enforce a
tool set the way a real agent definition can, and both directors are meant to use the host's
default capable model with full tool access. They are also slash-invocable after refresh. On
Antigravity they load as skills in the main session.

**Director scoping — check before using.** Some consuming projects' own `AGENTS.md`/`CLAUDE.md`
explicitly ban the Planner/Implementer/Parity/Admin split (e.g. a standing project rule like
"this repo is a learning vehicle, not a lab for multi-agent workflows — do not restore a
Planner/Implementer/Parity/Admin split"). On a project like that, use the relevant leaf skill
directly and in-session instead (e.g. `xcode-network-engineer` for a networking question,
`xcode-admin` for a one-off hygiene check) — never spin up a director against that project just
because this pack has one. `harness-routing` encodes this scoping check so Gemini doesn't invoke
a director-orchestrated flow where it isn't wanted.

### Roles (leaf skills the directors spawn)

- **`xcode-admin`** — repo hygiene and housekeeping: git pre-flight checks, stale-lock cleanup,
  notes-doc archiving, plain status reporting. Never writes code, never rules on decisions.
- **`xcode-implementer`** — writes a pre-brief before coding, implements a component/feature,
  builds and tests it, and files a completion report with before/after test counts and flagged
  judgment calls.
- **`xcode-quality-auditor`** — adversarial review; requests the host's strongest model. Two
  modes: **PARITY** (hand-traces ported Swift against the original C/C++ oracle, function by
  function) and **QUALITY** (reviews new/existing Swift work against `Plan.md`/tests/
  conventions, plus the relevant Apple-domain best-practice skills — SwiftUI, App Intents,
  accessibility, security). Files findings only; never writes fixes, never marks work done.

`swift-port-director` spawns the Quality Auditor in PARITY mode as a mandatory gate after every
full-track (oracle-comparable) component. `swift-project-director` uses QUALITY mode at its
discretion (Apple-domain full-track or a risky merge); otherwise `/review` or the director's own
diff check.

### Other skills

- **`director-operating-model`** — shared router both directors load: spawn rule, routing table
  (MCP, `/review`, worktrees, TDD, verification), doc scale, safety bars. Not a standalone role.
- **`refresh-team`** — wraps `scripts/refresh-team.sh` as `/refresh-team` in any linked CLI.
- **`xcode-network-engineer`** — accumulated Network.framework findings for Swift (both the
  structured-concurrency API and the older completion-handler API), plus a known EINVAL
  hosting-bug pattern.
- **`delphine-l-claude-collaboration`**, **`delphine-l-claude-skill-management`**,
  **`delphine-l-command-discipline`**, **`delphine-l-documentation`**,
  **`delphine-l-token-efficiency`** — general Claude Code working-practice skills pulled in from
  [Delphine-L/claude_global](https://github.com/Delphine-L/claude_global)'s `claude-meta`
  category (team collaboration, skill authoring/symlinking, bare shell-command style, session
  documentation, token-efficient tool use). Prefixed to avoid confusion with this repo's own
  conventions and with similarly-named skills from other sources (e.g.
  `superpowers:systematic-debugging`).

### How the director pack fits together (when it's used)

Each director maintains living documents scaled to the work (`Plan.md` + `agent_notes.md` for a
single session; add `DecisionLog.md` for multi-session; function-inventory and archive files for
a multi-week port). Role skills are project-agnostic: the director tells any worker which files
are plan doc and notes doc. Orient from the repo (never a stale summary). Verify with Xcode MCP
or `xcodebuild` before claiming done — a child "success" is not evidence. An entry that only
exists in chat is invisible to the next session.

### Marketplace (Claude + Grok)

This repo is a self-hosting marketplace: `.claude-plugin/marketplace.json` lists one plugin at
`source: "./"`, the same shape used by other self-hosting marketplaces. Skills stay one level
under `skills/` so the plugin loader finds them. Grok accepts the `.claude-plugin/` layout; there
is no separate `.grok-plugin/` copy.

Gemini and `agy` have no common marketplace with Claude/Grok. They keep using
`./scripts/refresh-team.sh`.

If you want to pull in more skills from an external collection like
[Delphine-L/claude_global](https://github.com/Delphine-L/claude_global), clone it locally as a
working checkout (gitignore it under `docs/` or elsewhere) and use it as a reference for that
project's own `skills/<category>/<name>/` layout — this repo does not depend on any such
checkout existing.
