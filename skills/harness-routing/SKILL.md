---
name: harness-routing
description: "Cross-harness routing rules for a Claude/Gemini/Grok workflow: which CLI does what, the daily trigger-phrase handoff loop, and when NOT to invoke a director-orchestrated flow. Use when deciding which harness or mode to use for a task, when the user says their configured daily trigger phrase (a plain \"good morning\" greeting is NOT the trigger and should get a plain reply), when continuing the daily status/handoff loop via a project's docs/STATUS.md, or when a project's AGENTS.md forbids a Planner/Implementer/Parity/Admin-style role split and you need to know what to do instead."
---

# Harness routing

Decision rules for using Claude Code, Gemini (agy/Antigravity), and Grok together without
re-deciding from scratch each day, and without accidentally re-running a director-orchestrated
multi-role flow on a project that has banned it.

## The daily loop

**Pick one exact trigger phrase and use it consistently** — e.g. `<YOUR TRIGGER PHRASE>` — say it
to Gemini to start the loop, and don't reuse a casual greeting for it. This is deliberate: you'll
talk to these CLIs throughout the day, and an ordinary "good morning" greeting must never
accidentally kick off task dispatch. Only your exact configured phrase starts the loop; a plain
greeting gets a plain reply, nothing more.

1. You say your trigger phrase to Gemini.
2. Gemini reads the active project's `docs/STATUS.md` (or equivalent status doc) and gives a
   status update, or proposes the next task.
3. Based on that conversation, Gemini dispatches the task to Claude or Grok (non-interactive/
   headless prompt mode — check each CLI's own `--help` for its exact flag before wiring this;
   don't assume flag names match across tools). The dispatched harness appends a short, dated
   entry to `docs/STATUS.md` when it finishes — append, never rewrite existing entries.
4. If Claude finishes work that needs GitHub bookkeeping (issue/board/status updates), Claude
   dispatches that follow-up to Grok the same way. Grok appends its own dated entry.
5. On the next trigger, Gemini reads the now-updated `docs/STATUS.md` and reports back.

**Decision-making is Gemini's role only.** This skill is symlinked identically into Claude,
Grok, and Gemini, so any of them can recognize the trigger phrase — but if Claude or Grok
receives it (e.g. you typed it into the wrong terminal), that harness should read
`docs/STATUS.md` and report status only, and explicitly say the "what's next" decision belongs
to Gemini — not independently propose or rank next-task options itself. If two harnesses each
run the full decision loop off the same trigger, they can produce two different, unreconciled
task menus, which recreates the coordination waste this loop exists to remove.

**Keep step 1 human-initiated.** Don't wire this to a cron/scheduler — the trigger phrase is the
one cheap human checkpoint in the chain. Steps 3–4 are automated *execution*, not an unattended
pipeline: each harness still asks before push or other destructive/hard-to-reverse actions even
when dispatched by another harness, unless you have explicitly granted a scoped autonomous
session.

**Don't dispatch by default.** Only hand off to Claude/Grok when the day's task actually needs
execution. A pure status day costs one Gemini read and zero handoffs. Each hop bootstraps a
fresh process (re-reads AGENTS.md/CLAUDE.md, its own skill listing, and docs/STATUS.md), so
chaining harnesses when it isn't needed burns more tokens than it saves. When a handoff does
happen, write enough into the `docs/STATUS.md` entry (task, relevant file paths, acceptance
check) that the next harness doesn't have to re-explore from zero.

## Which harness for which job

- **Gemini** — large-context ingestion and the daily status/decision role. Best for reading an
  entire repo, a long log, a big diff, or a stack of GitHub issues in one pass and producing a
  compressed briefing. Not for iterative edit/test loops.
- **Grok** — fast, cheap bookkeeping: issue triage, label/milestone updates, status-doc
  entries, PR bookkeeping. Not for deep multi-file reasoning or a project's own test-and-verify
  loop.
- **Claude Code** — implementation with tool access: the actual edit/build/test loop, using
  each project's real verification commands (e.g. `swift test --filter`). Don't have it
  re-read a whole repo from scratch when a Gemini briefing or a `docs/STATUS.md` handoff entry
  could hand it a compressed starting point instead.

**Sequential is the default.** Gemini briefs → Claude implements → Grok closes the bookkeeping
loop. Only run harnesses concurrently on genuinely independent tracks that don't touch the same
files or state (e.g. Claude on a feature branch while Grok clears an unrelated issue backlog).
Never run two harnesses concurrently against the same file — that's a duplicate-work risk, not
a parallelism win.

## Handling a stalled or overrun dispatch

Detecting a dispatch that ran out of budget or hung is straightforward — wrap it, don't guess:

- Run every headless dispatch under a wall-clock timeout, e.g. `timeout <N> claude -p ...` /
  `timeout <N> grok -p ...`, rather than letting a hung or runaway process run indefinitely.
- Treat a non-zero/timeout exit code, or output matching a known quota/limit error signature
  (context-length-exceeded, rate-limit, usage-limit-reached), as a stall.

**On a stall, do not assume a clean stopping point.** Check the actual branch state first
(`git status`, `git diff --stat`) before doing anything else — a hard cutoff mid-edit can leave
an uncommitted or broken partial change, not a tidy handoff.

**Do not hand the remaining work to a different harness.** Grok is not a substitute implementer
(see allocation model above); routing an interrupted implementation task to it either produces
worse output than Claude would, or pays the same context-bootstrap cost a second time for no
benefit. If the branch has a broken/uncommitted partial edit, prefer retrying with a fresh,
narrower dispatch on the *same* harness — a smaller scoped task informed by what the git diff
shows was actually attempted — over swapping harnesses mid-task.

Grok only picks up after a stall if the leftover work is itself bookkeeping-shaped (e.g. "record
in `docs/STATUS.md` that issue #<N> stalled and why, so the next loop surfaces it") — never as a
replacement for the interrupted implementation.

Record the stall itself in `docs/STATUS.md` (dated entry: what was attempted, where it stopped,
whether the working tree is clean) so the next trigger surfaces it rather than silently retrying
forever.

## Before implementing anything

Run `git log --oneline --grep="#<issue>"` (and check the GitHub issue/PR state) before writing
code for a numbered issue or feature, in any project. Re-implementing something already shipped
under the same issue number is a full re-exploration-and-implementation session wasted — worth
checking for every time, in any project.

## Testing during iteration

Iterate against the narrowest relevant test scope (e.g. `swift test --filter <Suite>`); run the
full suite only pre-commit/pre-PR, or let CI run it if the project has CI.

## Director-orchestrated flows

Some skills in this pack (`director-operating-model`, `swift-project-director`,
`swift-port-director`, and the leaf skills they orchestrate) exist to run a Planner/Implementer
/Parity/Admin-style team. **Check the target project's own `AGENTS.md`/`CLAUDE.md` before using
them.** If a project's own standing constraints ban that role split, use the relevant leaf skill
directly and in-session (e.g. `xcode-network-engineer`, `xcode-admin` for a one-off hygiene
check) — never spin up the director agent against that project just because the pack has one.
