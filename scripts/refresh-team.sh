#!/usr/bin/env bash
# Idempotent installer: symlink this repo's skills/ and agents/ into every
# detected AI CLI's documented skill/agent homes.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: refresh-team.sh [--dry-run] [--status] [--project DIR] [--only claude,grok,gemini,agy]
EOF
}

DRY_RUN=0
STATUS_ONLY=0
PROJECT=""
ONLY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --status) STATUS_ONLY=1; shift ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    --only) ONLY="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_SRC="$REPO_ROOT/skills"
AGENTS_SRC="$REPO_ROOT/agents"

want_cli() {
  name="$1"
  if [ -z "$ONLY" ]; then
    return 0
  fi
  case ",$ONLY," in
    *",$name,"*) return 0 ;;
    *) return 1 ;;
  esac
}

have_bin() {
  command -v "$1" >/dev/null 2>&1
}

list_skills() {
  [ -d "$SKILLS_SRC" ] || return 0
  find "$SKILLS_SRC" -mindepth 2 -maxdepth 2 -name SKILL.md -print 2>/dev/null \
    | sort \
    | while IFS= read -r skill_md; do
        dir="$(dirname "$skill_md")"
        printf '%s|%s\n' "$(basename "$dir")" "$dir"
      done
}

list_agents() {
  [ -d "$AGENTS_SRC" ] || return 0
  flat="$(mktemp -t refresh-team-agents)"
  names="$(mktemp -t refresh-team-agent-names)"
  find "$AGENTS_SRC" -maxdepth 1 -type f -name '*.md' -print 2>/dev/null | sort > "$flat"
  : > "$names"
  while IFS= read -r agent; do
    [ -n "$agent" ] || continue
    base="$(basename "$agent")"
    printf '%s\n' "$base" >> "$names"
    printf '%s|%s\n' "$base" "$agent"
  done < "$flat"
  find "$AGENTS_SRC" -mindepth 2 -maxdepth 2 \( -name AGENT.md -o -name '*.md' \) -print 2>/dev/null \
    | sort \
    | while IFS= read -r agent_md; do
        dir="$(dirname "$agent_md")"
        name="$(basename "$dir").md"
        if grep -Fxq "$name" "$names"; then
          continue
        fi
        base="$(basename "$agent_md")"
        if [ "$base" != "AGENT.md" ] && [ -f "$dir/AGENT.md" ]; then
          continue
        fi
        printf '%s|%s\n' "$name" "$agent_md"
      done
  rm -f "$flat" "$names"
}

# host|binary|kind|dest
# kind is skills or agents. agy gets three skill homes and no agents.
HOST_ROWS="
claude|claude|skills|$HOME/.claude/skills
claude|claude|agents|$HOME/.claude/agents
grok|grok|skills|$HOME/.grok/skills
grok|grok|agents|$HOME/.grok/agents
gemini|gemini|skills|$HOME/.gemini/skills
gemini|gemini|agents|$HOME/.gemini/agents
agy|agy|skills|$HOME/.gemini/config/skills
agy|agy|skills|$HOME/.gemini/antigravity/skills
agy|agy|skills|$HOME/.gemini/antigravity-cli/skills
"

if [ -n "$PROJECT" ]; then
  PROJECT="$(cd "$PROJECT" && pwd)"
  HOST_ROWS="${HOST_ROWS}
claude|claude|skills|$PROJECT/.claude/skills
claude|claude|agents|$PROJECT/.claude/agents
grok|grok|skills|$PROJECT/.grok/skills
grok|grok|agents|$PROJECT/.grok/agents
gemini|gemini|skills|$PROJECT/.gemini/skills
gemini|gemini|agents|$PROJECT/.gemini/agents
claude|claude|skills|$PROJECT/.agents/skills
grok|grok|skills|$PROJECT/.agents/skills
gemini|gemini|skills|$PROJECT/.agents/skills
agy|agy|skills|$PROJECT/.agents/skills
"
fi

do_ln() {
  src="$1"
  dest="$2"
  if [ "$DRY_RUN" -eq 1 ] || [ "$STATUS_ONLY" -eq 1 ]; then
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
      printf 'ok\t%s\n' "$dest"
    elif [ -e "$dest" ] || [ -L "$dest" ]; then
      printf 'would-replace\t%s\t->\t%s\n' "$dest" "$src"
    else
      printf 'would-link\t%s\t->\t%s\n' "$dest" "$src"
    fi
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    printf 'skipped\t%s\tnot-a-symlink\n' "$dest"
    return 0
  fi
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    printf 'ok\t%s\n' "$dest"
    return 0
  fi
  existed=0
  if [ -L "$dest" ] || [ -e "$dest" ]; then
    existed=1
  fi
  ln -sfn "$src" "$dest"
  if [ "$existed" -eq 0 ]; then
    printf 'new\t%s\t->\t%s\n' "$dest" "$src"
  else
    printf 'linked\t%s\t->\t%s\n' "$dest" "$src"
  fi
}

prune_stale() {
  dest_dir="$1"
  src_root="$2"
  [ -d "$dest_dir" ] || return 0
  for entry in "$dest_dir"/*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    [ -L "$entry" ] || continue
    target="$(readlink "$entry")"
    case "$target" in
      "$src_root"/*)
        if [ ! -e "$target" ]; then
          if [ "$DRY_RUN" -eq 1 ] || [ "$STATUS_ONLY" -eq 1 ]; then
            printf 'would-prune\t%s\n' "$entry"
          else
            rm -f "$entry"
            printf 'pruned\t%s\n' "$entry"
          fi
        fi
        ;;
    esac
  done
}

note() {
  printf '%s\n' "$1"
  case "$1" in
    new$'\t'*|would-link$'\t'*) new=$((new + 1)) ;;
    ok$'\t'*) ok=$((ok + 1)) ;;
    pruned$'\t'*|would-prune$'\t'*) pruned=$((pruned + 1)) ;;
    skipped$'\t'*) skipped=$((skipped + 1)) ;;
    linked$'\t'*|would-replace$'\t'*) linked=$((linked + 1)) ;;
  esac
}

new=0
ok=0
pruned=0
skipped=0
linked=0
seen_missing=""

SKILL_LIST="$(list_skills)"
AGENT_LIST="$(list_agents)"

while IFS= read -r row; do
  row="${row#"${row%%[![:space:]]*}"}"
  row="${row%"${row##*[![:space:]]}"}"
  [ -n "$row" ] || continue
  host="${row%%|*}"
  rest="${row#*|}"
  bin="${rest%%|*}"
  rest="${rest#*|}"
  kind="${rest%%|*}"
  dest_dir="${rest#*|}"

  want_cli "$host" || continue
  if ! have_bin "$bin"; then
    case " $seen_missing " in
      *" $host "*) ;;
      *) printf 'missing-cli\t%s\n' "$host"
         seen_missing="$seen_missing $host"
         ;;
    esac
    continue
  fi

  if [ "$kind" = "skills" ]; then
    while IFS= read -r pline; do
      [ -n "$pline" ] || continue
      note "$pline"
    done <<EOF
$(prune_stale "$dest_dir" "$SKILLS_SRC")
EOF
    while IFS= read -r item; do
      [ -n "$item" ] || continue
      name="${item%%|*}"
      src="${item#*|}"
      note "$(do_ln "$src" "$dest_dir/$name")"
    done <<EOF
$SKILL_LIST
EOF
  else
    while IFS= read -r pline; do
      [ -n "$pline" ] || continue
      note "$pline"
    done <<EOF
$(prune_stale "$dest_dir" "$AGENTS_SRC")
EOF
    while IFS= read -r item; do
      [ -n "$item" ] || continue
      name="${item%%|*}"
      src="${item#*|}"
      note "$(do_ln "$src" "$dest_dir/$name")"
    done <<EOF
$AGENT_LIST
EOF
  fi
done <<EOF
$HOST_ROWS
EOF

printf 'summary\tnew=%s\tok=%s\tpruned=%s\tskipped=%s\tlinked=%s\n' \
  "$new" "$ok" "$pruned" "$skipped" "$linked"
