#!/usr/bin/env bash
# PreToolUse hook: blocks merging into main unless /code-review was run on the
# exact commit being merged. After the review (and its fixes are committed),
# record it with: scripts/mark-reviewed.sh
#
# Covers: `git merge` while on main, `git push ... main` (including
# HEAD:main), `gh pr merge`, and the GitHub MCP merge_pull_request tool.
set -euo pipefail

input=$(cat)
tool=$(jq -r '.tool_name // ""' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")
[ -n "$cwd" ] || cwd=${CLAUDE_PROJECT_DIR:-$PWD}

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# Which repo the command runs in: a leading `cd DIR &&` or `git -C DIR` wins over the hook's cwd.
repo_for() {
  local cmd=$1 dir
  dir=$(sed -nE 's/^[[:space:]]*cd[[:space:]]+([^;&|[:space:]]+).*/\1/p' <<<"$cmd")
  [ -z "$dir" ] && dir=$(sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^;&|[:space:]]+).*/\1/p' <<<"$cmd")
  [ -n "$dir" ] && { case $dir in /*) echo "$dir" ;; *) echo "$cwd/$dir" ;; esac; return; }
  echo "$cwd"
}

check() { # $1 repo dir, $2 commit-ish being merged
  local repo=$1 rev=$2 sha marker reviewed
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || return 0 # not a git repo: nothing to guard
  # Only this repository (it has this hook file) carries the rule.
  [ -f "$(git -C "$repo" rev-parse --show-toplevel)/.claude/hooks/require-code-review.sh" ] || return 0
  sha=$(git -C "$repo" rev-parse --verify --quiet "$rev^{commit}" || true)
  [ -n "$sha" ] || deny "Merge into main blocked: couldn't resolve '$rev' to check its code review."
  marker="$(git -C "$repo" rev-parse --absolute-git-dir)/code-review-ok"
  reviewed=$(cat "$marker" 2>/dev/null || true)
  if [ "$reviewed" != "$sha" ]; then
    local last=${reviewed:-none}
    deny "Merge into main blocked: commit ${sha:0:9} has no code review. Run the /code-review skill (\`/code-review high\` against main), fix or answer every finding, commit, check every internal link and anchor (see README, Checks), then run scripts/mark-reviewed.sh and retry. (Last reviewed commit: ${last:0:9}.)"
  fi
}

case $tool in
  Bash)
    cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
    repo=$(repo_for "$cmd")
    # git push ... main / HEAD:main / src:main / refs/heads/main
    if grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]|$)' <<<"$cmd" &&
       grep -Eq '([[:space:]:]|refs/heads/)main([[:space:]]|$|[;&|])' <<<"$cmd"; then
      src=$(grep -Eo '[^[:space:]]+:(refs/heads/)?main([[:space:]]|$)' <<<"$cmd" | head -1 | cut -d: -f1 || true)
      if [ -n "$src" ]; then
        check "$repo" "$src"
      elif [ "$(git -C "$repo" branch --show-current 2>/dev/null)" = main ]; then
        check "$repo" HEAD
      else
        check "$repo" main
      fi
    fi
    # git merge while on main: the merged branch is what needs the review
    if grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+merge[[:space:]]' <<<"$cmd" &&
       [ "$(git -C "$repo" branch --show-current 2>/dev/null)" = main ]; then
      branch=$(sed -nE 's/.*git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+merge[[:space:]]+(-[^[:space:]]+[[:space:]]+)*([^-;&|[:space:]][^;&|[:space:]]*).*/\3/p' <<<"$cmd")
      [ -n "$branch" ] && check "$repo" "$branch"
    fi
    # gh pr merge (no gh here, but in case): the checked-out branch must be the reviewed one
    if grep -Eq '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+merge' <<<"$cmd"; then
      check "$repo" HEAD
    fi
    ;;
  mcp__github__merge_pull_request)
    # The PR's head should be the branch checked out here; it must be the reviewed commit.
    repo=${CLAUDE_PROJECT_DIR:-$cwd}
    [ -d "$repo/.git" ] || repo=$cwd
    check "$repo" HEAD
    ;;
esac
exit 0
