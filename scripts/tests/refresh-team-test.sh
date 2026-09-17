#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d /tmp/refresh-team-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/home"
export HOME="$TMP/home"
export PATH="$TMP/bin:/usr/bin:/bin"

# Only grok + gemini exist in the fixture. claude and agy are absent.
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/grok"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/gemini"
chmod +x "$TMP/bin/grok" "$TMP/bin/gemini"

"$ROOT/scripts/refresh-team.sh" > "$TMP/out"

grep -q 'missing-cli	claude' "$TMP/out"
grep -q 'missing-cli	agy' "$TMP/out"
test -L "$HOME/.grok/skills/xcode-admin"
test "$(readlink "$HOME/.grok/skills/xcode-admin")" = "$ROOT/skills/xcode-admin"
test -L "$HOME/.grok/skills/director-operating-model"
test "$(readlink "$HOME/.grok/skills/director-operating-model")" = "$ROOT/skills/director-operating-model"
test -L "$HOME/.grok/agents/swift-project-director.md"
test -L "$HOME/.gemini/skills/xcode-admin"
test ! -e "$HOME/.claude/skills/xcode-admin"
test ! -e "$HOME/.gemini/config/skills/xcode-admin"

# Idempotent second run still exits 0
"$ROOT/scripts/refresh-team.sh" >/dev/null

# Real directory at dest is skipped, not replaced
mkdir -p "$HOME/.grok/skills/keep-me-real"
printf 'nope\n' > "$HOME/.grok/skills/keep-me-real/SKILL.md"
# The installer only links names that exist in the repo. Simulate a collision
# by replacing xcode-admin with a real dir after unlinking.
rm "$HOME/.grok/skills/xcode-admin"
mkdir -p "$HOME/.grok/skills/xcode-admin"
printf 'local\n' > "$HOME/.grok/skills/xcode-admin/SKILL.md"
"$ROOT/scripts/refresh-team.sh" > "$TMP/out2"
grep -q 'skipped	.*xcode-admin	not-a-symlink' "$TMP/out2"
test -f "$HOME/.grok/skills/xcode-admin/SKILL.md"

# --project links .agents/skills as well
mkdir -p "$TMP/proj"
"$ROOT/scripts/refresh-team.sh" --project "$TMP/proj" >/dev/null
test -L "$TMP/proj/.grok/skills/xcode-admin"
test -L "$TMP/proj/.agents/skills/xcode-admin"

# Recreate the skipped dest as a symlink so later new-detection is clean
rm -rf "$HOME/.grok/skills/xcode-admin"
"$ROOT/scripts/refresh-team.sh" >/dev/null

# Missing dest is new: --status would-link, live new
rm -f "$HOME/.grok/skills/director-operating-model"
"$ROOT/scripts/refresh-team.sh" --status > "$TMP/st"
grep -q 'would-link	.*director-operating-model' "$TMP/st"
grep -q '^summary	' "$TMP/st"
"$ROOT/scripts/refresh-team.sh" > "$TMP/out3"
grep -q 'new	.*director-operating-model' "$TMP/out3"
grep -q '^summary	' "$TMP/out3"
test -L "$HOME/.grok/skills/director-operating-model"

# Second live run reports ok for the dest we just created
"$ROOT/scripts/refresh-team.sh" > "$TMP/out4"
grep -q "ok	$HOME/.grok/skills/director-operating-model" "$TMP/out4"
