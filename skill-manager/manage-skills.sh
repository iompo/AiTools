#!/usr/bin/env bash
#
# manage-skills.sh — manage a central collection of Claude skills, make them
# available across ALL your projects, and keep them updated from upstream.
#
# Single source of truth:  claude-custom/skills/<name>/SKILL.md
# Made global by symlinking each skill into ~/.claude/skills/, which Claude
# Code automatically discovers in every project on your machine.
#
# Tools (scripts that skills or hooks rely on, e.g. ticket-flow's ctx-report.py)
# live in claude-custom/tools/<name>/ and are linked into ~/.claude/tools/<name>.
# They are tracked the same way, git sources only, and need no SKILL.md.
#
# Each skill folder may contain a `.source` file recording where it came from,
# enabling `update` to re-fetch the latest version. Two source types:
#   type=git   repo=<git-url>  path=<path-in-repo>  ref=<branch-or-tag>
#   type=url   url=<raw-url-to-SKILL.md>
#
# Usage:
#   ./manage-skills.sh list                    List skills and tools in the local collection
#   ./manage-skills.sh installed               List skills and tools currently active globally
#   ./manage-skills.sh sync                    Link every skill into ~/.claude/skills and
#                                              every tool into ~/.claude/tools
#   ./manage-skills.sh add <name> <url>        Add a skill (auto-detects GitHub URLs)
#   ./manage-skills.sh add-git <name> <repo-url> <path> [ref]
#                                              Add a skill from a git repo explicitly
#   ./manage-skills.sh add-tool <name> <github-tree-url>
#                                              Add a tool folder (auto-detects GitHub URLs)
#   ./manage-skills.sh add-tool-git <name> <repo-url> <path> [ref]
#                                              Add a tool folder from a git repo explicitly
#   ./manage-skills.sh update [<name>]         Re-fetch one skill or tool, or all if no name given
#   ./manage-skills.sh remove <name>           Remove a skill's or tool's global link (keeps source)
#   ./manage-skills.sh link-project <path>     Copy skills into a project's .claude/skills
#   ./manage-skills.sh help                    Show this help
#
set -euo pipefail

# --- Paths -------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/skills"
CACHE_DIR="$SCRIPT_DIR/.cache/repos"
CLAUDE_GLOBAL_SKILLS="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
TOOLS_SRC="$SCRIPT_DIR/tools"
CLAUDE_GLOBAL_TOOLS="${CLAUDE_TOOLS_DIR:-$HOME/.claude/tools}"

# --- Helpers -----------------------------------------------------------------

info()  { printf '\033[0;36m%s\033[0m\n' "$*"; }
ok()    { printf '\033[0;32m%s\033[0m\n' "$*"; }
warn()  { printf '\033[0;33m%s\033[0m\n' "$*" >&2; }
die()   { printf '\033[0;31mError: %s\033[0m\n' "$*" >&2; exit 1; }

is_skill() { [ -f "$1/SKILL.md" ]; }

# A tool folder counts once it holds anything besides our metadata.
is_tool() {
  [ -d "$1" ] && [ -n "$(find "$1" -mindepth 1 -maxdepth 1 ! -name .source ! -name .DS_Store -print -quit)" ]
}

# Source root for a kind of entry: skill | tool
root_of() { if [ "$1" = tool ]; then echo "$TOOLS_SRC"; else echo "$SKILLS_SRC"; fi; }

# Parse a GitHub tree URL into REPO, REF, PATH_IN_REPO; returns 1 if it isn't one.
parse_github_tree() {
  if [[ "$1" =~ ^https?://github\.com/([^/]+)/([^/]+)/tree/([^/]+)/(.+)$ ]]; then
    REPO="https://github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}.git"
    REF="${BASH_REMATCH[3]}"
    PATH_IN_REPO="${BASH_REMATCH[4]%/}"
    return 0
  fi
  return 1
}

source_get() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  grep -m1 "^${key}=" "$file" 2>/dev/null | sed "s/^${key}=//" || true
}

sanitize_repo() {
  echo "$1" | sed -E 's|^https?://||; s|^git@||; s|[:/]|_|g; s|\.git$||'
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "$1 is required but not installed"; }

# --- Source fetch primitives -------------------------------------------------

fetch_git() {
  # Clones/updates the upstream repo into the cache, then copies the requested
  # path into the skill (or tool) folder. Preserves .source.
  local name="$1" repo="$2" path="$3" ref="$4" kind="${5:-skill}"
  require_cmd git
  local cache="$CACHE_DIR/$(sanitize_repo "$repo")"
  mkdir -p "$CACHE_DIR"
  if [ ! -d "$cache/.git" ]; then
    info "  cloning $repo"
    git clone --quiet "$repo" "$cache" || die "git clone failed for $repo"
  fi
  ( cd "$cache" \
      && git fetch --quiet --all --prune \
      && git checkout --quiet "$ref" \
      && git reset --quiet --hard "origin/$ref" 2>/dev/null \
  ) || warn "  (git sync had issues — continuing with current checkout)"
  local src="$cache/$path"
  [ -d "$src" ]            || die "Path '$path' not found in $repo @ $ref"
  if [ "$kind" = skill ]; then
    [ -f "$src/SKILL.md" ] || die "No SKILL.md at $repo/$path"
  fi
  local dir; dir="$(root_of "$kind")/$name"
  local saved_source=""
  [ -f "$dir/.source" ] && saved_source="$(cat "$dir/.source")"
  rm -rf "$dir"
  mkdir -p "$dir"
  cp -R "$src/." "$dir/"
  if [ -n "$saved_source" ]; then
    printf '%s\n' "$saved_source" > "$dir/.source"
  fi
  ok "  fetched $kind $name from $repo ($ref) :: $path"
}

fetch_url() {
  local name="$1" url="$2"
  require_cmd curl
  local dir="$SKILLS_SRC/$name"
  mkdir -p "$dir"
  curl -fsSL "$url" -o "$dir/SKILL.md" || die "curl failed for $url"
  ok "  fetched $name from $url"
}

write_source_git() {
  local name="$1" repo="$2" path="$3" ref="$4" kind="${5:-skill}"
  local dir; dir="$(root_of "$kind")/$name"
  mkdir -p "$dir"
  cat > "$dir/.source" <<SRC_EOF
type=git
repo=$repo
path=$path
ref=$ref
SRC_EOF
}

write_source_url() {
  local name="$1" url="$2"
  local dir="$SKILLS_SRC/$name"
  mkdir -p "$dir"
  cat > "$dir/.source" <<SRC_EOF
type=url
url=$url
SRC_EOF
}

# --- Commands ----------------------------------------------------------------

cmd_list() {
  [ -d "$SKILLS_SRC" ] || die "No skills directory at $SKILLS_SRC"
  info "Skills in the collection ($SKILLS_SRC):"
  local found=0
  for dir in "$SKILLS_SRC"/*/; do
    [ -d "$dir" ] || continue
    local name; name="$(basename "$dir")"
    if is_skill "$dir"; then
      found=1
      local desc src_type src_label=""
      desc="$(grep -m1 '^description:' "$dir/SKILL.md" 2>/dev/null | sed 's/^description:[[:space:]]*//' || true)"
      src_type="$(source_get "$dir/.source" type)"
      case "$src_type" in
        git) src_label=" [git: $(source_get "$dir/.source" repo)@$(source_get "$dir/.source" ref)]" ;;
        url) src_label=" [url]" ;;
        '')  src_label=" [no source recorded]" ;;
      esac
      printf '  - %-20s%s\n      %s\n' "$name" "$src_label" "${desc:-(no description)}"
    else
      printf '  - %-20s (missing SKILL.md — skipped on sync)\n' "$name"
    fi
  done
  [ "$found" -eq 1 ] || warn "  (none yet — add one with: $0 add <name> <url>)"
  [ -d "$TOOLS_SRC" ] || return 0
  info "Tools in the collection ($TOOLS_SRC):"
  for dir in "$TOOLS_SRC"/*/; do
    [ -d "$dir" ] || continue
    local tname tsrc files
    tname="$(basename "$dir")"
    tsrc=" [no source recorded]"
    if [ "$(source_get "$dir/.source" type)" = git ]; then
      tsrc=" [git: $(source_get "$dir/.source" repo)@$(source_get "$dir/.source" ref)]"
    fi
    files="$(find "$dir" -mindepth 1 -maxdepth 1 ! -name .source ! -name .DS_Store -exec basename {} \; | sort | paste -sd ' ' -)"
    printf '  - %-20s%s\n      %s\n' "$tname" "$tsrc" "${files:-(empty — skipped on sync)}"
  done
}

cmd_installed() {
  if [ ! -d "$CLAUDE_GLOBAL_SKILLS" ]; then
    warn "Global skills dir does not exist yet: $CLAUDE_GLOBAL_SKILLS"
    warn "Run: $0 sync"
    return 0
  fi
  info "Skills active globally ($CLAUDE_GLOBAL_SKILLS):"
  local found=0
  for dir in "$CLAUDE_GLOBAL_SKILLS"/*/; do
    [ -e "$dir" ] || continue
    found=1
    local name; name="$(basename "$dir")"
    if [ -L "${dir%/}" ]; then
      printf '  - %-20s -> %s\n' "$name" "$(readlink "${dir%/}")"
    else
      printf '  - %-20s (plain copy)\n' "$name"
    fi
  done
  [ "$found" -eq 1 ] || warn "  (nothing linked yet — run: $0 sync)"
  [ -d "$CLAUDE_GLOBAL_TOOLS" ] || return 0
  info "Tools active globally ($CLAUDE_GLOBAL_TOOLS):"
  for dir in "$CLAUDE_GLOBAL_TOOLS"/*/; do
    [ -e "$dir" ] || continue
    local tname; tname="$(basename "$dir")"
    if [ -L "${dir%/}" ]; then
      printf '  - %-20s -> %s\n' "$tname" "$(readlink "${dir%/}")"
    else
      printf '  - %-20s (plain copy)\n' "$tname"
    fi
  done
}

cmd_sync() {
  [ -d "$SKILLS_SRC" ] || die "No skills directory at $SKILLS_SRC"
  mkdir -p "$CLAUDE_GLOBAL_SKILLS"
  info "Syncing skills into $CLAUDE_GLOBAL_SKILLS ..."
  local count=0
  for dir in "$SKILLS_SRC"/*/; do
    [ -d "$dir" ] || continue
    local name; name="$(basename "$dir")"
    if ! is_skill "$dir"; then
      warn "  skip $name (no SKILL.md)"
      continue
    fi
    local target="$CLAUDE_GLOBAL_SKILLS/$name"
    [ -L "$target" ] || [ -e "$target" ] && rm -rf "$target"
    ln -s "${dir%/}" "$target"
    ok "  linked $name"
    count=$((count + 1))
  done
  ok "Done. $count skill(s) available across all your projects."
  [ -d "$TOOLS_SRC" ] || return 0
  mkdir -p "$CLAUDE_GLOBAL_TOOLS"
  info "Syncing tools into $CLAUDE_GLOBAL_TOOLS ..."
  local tcount=0
  for dir in "$TOOLS_SRC"/*/; do
    [ -d "$dir" ] || continue
    local tname; tname="$(basename "$dir")"
    if ! is_tool "$dir"; then
      warn "  skip $tname (empty)"
      continue
    fi
    local ttarget="$CLAUDE_GLOBAL_TOOLS/$tname"
    if [ -L "$ttarget" ] || [ -e "$ttarget" ]; then rm -rf "$ttarget"; fi
    ln -s "${dir%/}" "$ttarget"
    ok "  linked $tname"
    tcount=$((tcount + 1))
  done
  ok "Done. $tcount tool(s) linked."
}

cmd_add() {
  local name="${1:-}" source="${2:-}"
  [ -n "$name" ]   || die "Usage: $0 add <name> <url-or-source>"
  [ -n "$source" ] || die "Usage: $0 add <name> <url-or-source>"

  # GitHub tree URL: https://github.com/<owner>/<repo>/tree/<ref>/<path>
  if [[ "$source" =~ ^https?://github\.com/([^/]+)/([^/]+)/tree/([^/]+)/(.+)$ ]]; then
    local repo="https://github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}.git"
    local ref="${BASH_REMATCH[3]}" path="${BASH_REMATCH[4]}"
    info "Detected GitHub repo: $repo ($ref) path=$path"
    write_source_git "$name" "$repo" "$path" "$ref"
    fetch_git "$name" "$repo" "$path" "$ref"

  # GitHub blob URL: https://github.com/<owner>/<repo>/blob/<ref>/<path>/SKILL.md
  elif [[ "$source" =~ ^https?://github\.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)/SKILL\.md$ ]]; then
    local repo="https://github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}.git"
    local ref="${BASH_REMATCH[3]}" path="${BASH_REMATCH[4]}"
    info "Detected GitHub blob URL: $repo ($ref) path=$path"
    write_source_git "$name" "$repo" "$path" "$ref"
    fetch_git "$name" "$repo" "$path" "$ref"

  # raw.githubusercontent.com/<owner>/<repo>/<ref>/<path>/SKILL.md → also treat as git
  elif [[ "$source" =~ ^https?://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/(.+)/SKILL\.md$ ]]; then
    local repo="https://github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}.git"
    local ref="${BASH_REMATCH[3]}" path="${BASH_REMATCH[4]}"
    info "Detected GitHub raw URL: $repo ($ref) path=$path"
    write_source_git "$name" "$repo" "$path" "$ref"
    fetch_git "$name" "$repo" "$path" "$ref"

  # Anything else: treat as a plain URL to a SKILL.md file.
  else
    info "Treating as plain URL: $source"
    write_source_url "$name" "$source"
    fetch_url "$name" "$source"
  fi

  ok "Added '$name'. Run '$0 sync' to make it available everywhere."
}

cmd_add_git() {
  local name="${1:-}" repo="${2:-}" path="${3:-}" ref="${4:-main}"
  [ -n "$name" ] && [ -n "$repo" ] && [ -n "$path" ] \
    || die "Usage: $0 add-git <name> <repo-url> <path-in-repo> [ref]"
  write_source_git "$name" "$repo" "$path" "$ref"
  fetch_git "$name" "$repo" "$path" "$ref"
  ok "Added '$name'. Run '$0 sync' to make it available everywhere."
}

cmd_add_tool() {
  local name="${1:-}" source="${2:-}"
  [ -n "$name" ] && [ -n "$source" ] || die "Usage: $0 add-tool <name> <github-tree-url>"
  parse_github_tree "$source" \
    || die "Not a GitHub folder URL: $source — use: $0 add-tool-git <name> <repo-url> <path> [ref]"
  info "Detected GitHub repo: $REPO ($REF) path=$PATH_IN_REPO"
  write_source_git "$name" "$REPO" "$PATH_IN_REPO" "$REF" tool
  fetch_git "$name" "$REPO" "$PATH_IN_REPO" "$REF" tool
  ok "Added tool '$name'. Run '$0 sync' to link it into $CLAUDE_GLOBAL_TOOLS."
}

cmd_add_tool_git() {
  local name="${1:-}" repo="${2:-}" path="${3:-}" ref="${4:-main}"
  [ -n "$name" ] && [ -n "$repo" ] && [ -n "$path" ] \
    || die "Usage: $0 add-tool-git <name> <repo-url> <path-in-repo> [ref]"
  write_source_git "$name" "$repo" "$path" "$ref" tool
  fetch_git "$name" "$repo" "$path" "$ref" tool
  ok "Added tool '$name'. Run '$0 sync' to link it into $CLAUDE_GLOBAL_TOOLS."
}

cmd_update() {
  local name="${1:-}"
  if [ -n "$name" ]; then
    update_one "$name"
  else
    info "Updating all skills with recorded sources ..."
    local any=0
    for dir in "$SKILLS_SRC"/*/; do
      [ -d "$dir" ] || continue
      local n; n="$(basename "$dir")"
      if [ -f "$dir/.source" ]; then
        any=1
        update_one "$n" || warn "  (continuing despite error in $n)"
      else
        warn "  skip $n (no .source — added manually?)"
      fi
    done
    for dir in "$TOOLS_SRC"/*/; do
      [ -d "$dir" ] || continue
      local tn; tn="$(basename "$dir")"
      if [ -f "$dir/.source" ]; then
        any=1
        update_one "$tn" tool || warn "  (continuing despite error in tool $tn)"
      else
        warn "  skip tool $tn (no .source — added manually?)"
      fi
    done
    [ "$any" -eq 1 ] || warn "Nothing to update."
  fi
}

update_one() {
  local name="$1" kind="${2:-}"
  if [ -z "$kind" ]; then
    if [ -d "$SKILLS_SRC/$name" ] && [ -d "$TOOLS_SRC/$name" ]; then
      die "'$name' is both a skill and a tool — rename one of them"
    fi
    if [ -d "$TOOLS_SRC/$name" ]; then kind=tool; else kind=skill; fi
  fi
  local dir; dir="$(root_of "$kind")/$name"
  [ -d "$dir" ]         || die "No such skill or tool: $name"
  [ -f "$dir/.source" ] || die "No .source file in $dir — can't update. Re-add with: $0 add $name <url>"
  local type; type="$(source_get "$dir/.source" type)"
  case "$type" in
    git)
      local repo path ref
      repo="$(source_get "$dir/.source" repo)"
      path="$(source_get "$dir/.source" path)"
      ref="$(source_get  "$dir/.source" ref)"
      ref="${ref:-main}"
      [ -n "$repo" ] && [ -n "$path" ] || die "Malformed .source for $name (need repo= and path=)"
      fetch_git "$name" "$repo" "$path" "$ref" "$kind"
      ;;
    url)
      [ "$kind" = skill ] || die "Tool $name: only git sources are supported for tools"
      local url; url="$(source_get "$dir/.source" url)"
      [ -n "$url" ] || die "Malformed .source for $name (need url=)"
      fetch_url "$name" "$url"
      ;;
    *)
      die "Unknown source type '$type' in $dir/.source"
      ;;
  esac
}

cmd_remove() {
  local name="${1:-}"
  [ -n "$name" ] || die "Usage: $0 remove <name>"
  local removed=0 target
  for target in "$CLAUDE_GLOBAL_SKILLS/$name" "$CLAUDE_GLOBAL_TOOLS/$name"; do
    if [ -L "$target" ] || [ -e "$target" ]; then
      rm -rf "$target"
      ok "Removed global link $target. Source kept in $SCRIPT_DIR."
      removed=1
    fi
  done
  [ "$removed" -eq 1 ] || warn "'$name' is not linked in $CLAUDE_GLOBAL_SKILLS or $CLAUDE_GLOBAL_TOOLS — nothing to do."
}

cmd_link_project() {
  local proj="${1:-}"
  [ -n "$proj" ] || die "Usage: $0 link-project <path-to-project>"
  [ -d "$proj" ] || die "No such directory: $proj"
  local dest="$proj/.claude/skills"
  mkdir -p "$dest"
  info "Copying skills into $dest ..."
  local count=0
  for dir in "$SKILLS_SRC"/*/; do
    [ -d "$dir" ] || continue
    is_skill "$dir" || continue
    local name; name="$(basename "$dir")"
    rm -rf "$dest/$name"
    cp -R "${dir%/}" "$dest/$name"
    # Strip our internal .source file from the copy — it's metadata for our tool.
    rm -f "$dest/$name/.source"
    ok "  copied $name"
    count=$((count + 1))
  done
  ok "Done. $count skill(s) copied into the project (commit them to share with your team)."
}

usage() {
  awk 'NR>1 && /^set -euo pipefail/ {exit} NR>1 {sub(/^# ?/, ""); print}' "${BASH_SOURCE[0]}"
}

# --- Dispatch ----------------------------------------------------------------

main() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    list)           cmd_list "$@" ;;
    installed)      cmd_installed "$@" ;;
    sync)           cmd_sync "$@" ;;
    add)            cmd_add "$@" ;;
    add-git)        cmd_add_git "$@" ;;
    add-tool)       cmd_add_tool "$@" ;;
    add-tool-git)   cmd_add_tool_git "$@" ;;
    update)         cmd_update "$@" ;;
    remove)         cmd_remove "$@" ;;
    link-project)   cmd_link_project "$@" ;;
    help|-h|--help) usage ;;
    *) die "Unknown command '$cmd'. Run '$0 help'." ;;
  esac
}

main "$@"
