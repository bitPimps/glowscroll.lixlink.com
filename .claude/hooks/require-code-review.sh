#!/usr/bin/env bash
# PreToolUse hook: blocks merging into main unless /code-review was run on the
# exact commit being merged. After the review (and its fixes are committed),
# record it with: scripts/mark-reviewed.sh
#
# Covers: `git merge` while on main, `git push` that updates main (explicit
# refspec, `--all`/`--mirror`, or a bare push while on main), `gh pr merge N`
# and the GitHub MCP merge_pull_request tool (checked against the PR's head
# commit on GitHub).
set -uo pipefail

CHECKS='check every internal link and anchor (README, Checks)'

input=$(cat)

deny() {
  local r=$1
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg r "$r" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
    exit 0
  fi
  echo "$r" >&2
  exit 2 # blocking error, even without jq
}

# Without jq nothing can be checked: block anything that might merge or push, allow the rest.
if ! command -v jq >/dev/null 2>&1; then
  if grep -Eq 'merge_pull_request|git[^"]*(push|merge)|gh[^"]*pr[^"]*merge' <<<"$input"; then
    deny "Merge guard can't run without jq, so pushes and merges are blocked. Install jq."
  fi
  exit 0
fi

tool=$(jq -r '.tool_name // ""' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")
[ -n "$cwd" ] || cwd=${CLAUDE_PROJECT_DIR:-$PWD}

# Which repo the command runs in: a leading `cd DIR &&` or `git -C DIR` wins over the hook's cwd.
repo_for() {
  local cmd=$1 dir
  dir=$(sed -nE 's/^[[:space:]]*cd[[:space:]]+([^;&|[:space:]]+).*/\1/p' <<<"$cmd")
  [ -z "$dir" ] && dir=$(sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^;&|[:space:]]+).*/\1/p' <<<"$cmd")
  [ -n "$dir" ] && { case $dir in /*) echo "$dir" ;; *) echo "$cwd/$dir" ;; esac; return; }
  echo "$cwd"
}

guarded() { # repo carries the rule (has this hook file)
  local top
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -f "$top/.claude/hooks/require-code-review.sh" ]
}

require_reviewed() { # $1 repo dir, $2 sha being merged
  local repo=$1 sha=$2 marker reviewed last
  marker="$(git -C "$repo" rev-parse --absolute-git-dir)/code-review-ok"
  reviewed=$(cat "$marker" 2>/dev/null || true)
  if [ "$reviewed" != "$sha" ]; then
    last=${reviewed:-none}
    deny "Merge into main blocked: commit ${sha:0:9} has no code review. Run the /code-review skill (\`/code-review high\` against main), fix or answer every finding, commit, $CHECKS, then run scripts/mark-reviewed.sh and retry. (Last reviewed commit: ${last:0:9}.)"
  fi
}

check_rev() { # $1 repo dir, $2 local commit-ish
  guarded "$1" || return 0
  local sha
  sha=$(git -C "$1" rev-parse --verify --quiet "$2^{commit}" || true)
  [ -n "$sha" ] || deny "Merge into main blocked: couldn't resolve '$2' to check its code review."
  require_reviewed "$1" "$sha"
}

check_pr() { # $1 repo dir, $2 PR number: the head commit as GitHub has it
  guarded "$1" || return 0
  local sha
  sha=$(git -C "$1" ls-remote origin "refs/pull/$2/head" 2>/dev/null | cut -f1)
  [ -n "$sha" ] || deny "Merge into main blocked: couldn't read PR #$2's head commit to check its code review."
  require_reviewed "$1" "$sha"
}

case $tool in
  Bash)
    cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
    repo=$(repo_for "$cmd")
    current=$(git -C "$repo" branch --show-current 2>/dev/null || true)

    if grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]|$)' <<<"$cmd"; then
      push_args=$(sed -nE 's/.*git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]+(.*))?$/\3/p' <<<"$cmd" | sed -E 's/[;&|].*//')
      if grep -Eq '(^|[[:space:]])--(all|mirror)([[:space:]]|$)' <<<"$push_args"; then
        check_rev "$repo" main
      elif src=$(grep -Eo '[^[:space:]]*:(refs/heads/)?main([[:space:]]|$)' <<<"$push_args" | head -1) && [ -n "$src" ]; then
        src=${src%%:*}
        check_rev "$repo" "${src:-HEAD}"
      elif grep -Eq '(^|[[:space:]])(refs/heads/)?main([[:space:]]|$)' <<<"$push_args"; then
        check_rev "$repo" main
      else
        # No refspec naming main: what gets pushed is the current branch (or its upstream).
        positional=$(tr ' ' '\n' <<<"$push_args" | grep -Ev '^(-|$)' | wc -l)
        if [ "$current" = main ] && [ "$positional" -le 1 ]; then check_rev "$repo" HEAD; fi
      fi
    fi

    # git merge while on main: the merged branch is what needs the review
    if grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+merge[[:space:]]' <<<"$cmd" && [ "$current" = main ]; then
      branch=$(sed -nE 's/.*git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+merge[[:space:]]+(-[^[:space:]]+[[:space:]]+)*([^-;&|[:space:]][^;&|[:space:]]*).*/\3/p' <<<"$cmd")
      [ -n "$branch" ] && check_rev "$repo" "$branch"
    fi

    if grep -Eq '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+merge' <<<"$cmd"; then
      pr=$(grep -Eo 'gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+([^[:space:]]+[[:space:]]+)*#?[0-9]+' <<<"$cmd" | grep -Eo '[0-9]+$' | head -1)
      if [ -n "$pr" ]; then check_pr "$repo" "$pr"; else guarded "$repo" && deny "Merge into main blocked: give gh pr merge a PR number so its head commit can be checked for a code review."; fi
    fi
    ;;
  mcp__github__merge_pull_request)
    pr=$(jq -r '.tool_input.pullNumber // .tool_input.pull_number // ""' <<<"$input")
    repo_name=$(jq -r '.tool_input.repo // ""' <<<"$input")
    # The clone for that repository: the session's project, or a sibling folder named after it.
    repo=${CLAUDE_PROJECT_DIR:-$cwd}
    for candidate in "$cwd" "$cwd/$repo_name" "$(dirname "$cwd")/$repo_name" "$repo"; do
      if [ -n "$repo_name" ] && git -C "$candidate" remote get-url origin 2>/dev/null | grep -qi "/$repo_name\(\.git\)\?$"; then
        repo=$candidate
        break
      fi
    done
    [ -n "$pr" ] && check_pr "$repo" "$pr"
    ;;
esac
exit 0
