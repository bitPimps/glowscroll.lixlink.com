#!/usr/bin/env bash
# Claude Code PreToolUse hook. The real gate is the git pre-push hook
# (.githooks/pre-push), which sees exactly which refs a push updates. This
# hook keeps that gate switched on and unbypassed, and guards the ways to
# change main that don't go through git push: merging a pull request and
# committing through the GitHub tools. See AGENTS.md.
set -uo pipefail

input=$(cat)

deny() {
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
    exit 0
  fi
  echo "$1" >&2
  exit 2
}

if ! command -v jq >/dev/null 2>&1; then
  grep -Eq 'push|merge|github' <<<"$input" && deny "The merge guard needs jq, so pushes and merges are blocked until jq is installed."
  exit 0
fi

tool=$(jq -r '.tool_name // ""' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")
[ -n "$cwd" ] || cwd=${CLAUDE_PROJECT_DIR:-$PWD}

guarded() { # a clone that carries this rule
  local top
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -f "$top/.githooks/pre-push" ]
}

reviewed_sha() { cat "$(git -C "$1" rev-parse --absolute-git-dir)/code-review-ok" 2>/dev/null || true; }

# Clones near the session: the cwd, the project, and folders next to or inside them.
candidates() {
  local base
  for base in "$cwd" "${CLAUDE_PROJECT_DIR:-}"; do
    [ -n "$base" ] || continue
    echo "$base"
    for d in "$base"/*/ "$(dirname "$base")"/*/; do [ -d "$d/.git" ] && echo "${d%/}"; done
  done | awk '!seen[$0]++'
}

clone_of() { # $1 owner, $2 repo: a local clone whose origin is exactly that repository
  local want d url
  want=$(tr '[:upper:]' '[:lower:]' <<<"$1/$2")
  while read -r d; do
    url=$(git -C "$d" remote get-url origin 2>/dev/null | tr '[:upper:]' '[:lower:]') || continue
    url=${url%.git}
    [ "${url##*github.com[:/]}" = "$want" ] && { echo "$d"; return 0; }
  done < <(candidates)
  return 1
}

check_pr() { # $1 clone, $2 PR number
  local sha reviewed
  sha=$(git -C "$1" ls-remote origin "refs/pull/$2/head" 2>/dev/null | cut -f1)
  [ -n "$sha" ] || deny "Merge blocked: couldn't read PR #$2's head commit to check its code review."
  reviewed=$(reviewed_sha "$1")
  [ "$sha" = "$reviewed" ] ||
    deny "Merge blocked: PR #$2's head ${sha:0:9} has no code review. Run /code-review high against main, fix or answer every finding, commit and push, run the checks in AGENTS.md, then scripts/mark-reviewed.sh and retry. (Last reviewed commit: ${reviewed:-none}.)"
}

case $tool in
  Bash)
    cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
    # Switching the git hooks off, or skipping them.
    # git config keys aren't case-sensitive.
    if grep -Eiq 'core\.hookspath' <<<"$cmd" && ! grep -Eiq 'core\.hookspath[= ]+\.githooks([[:space:]]|$|[;&|])' <<<"$cmd"; then
      deny "Changing core.hooksPath away from .githooks is blocked: it switches off the review guard."
    fi
    if grep -Eq 'push' <<<"$cmd" && grep -Eq -- '--no-verify' <<<"$cmd"; then
      deny "git push --no-verify is blocked: it skips the review guard."
    fi
    # A push from a guarded clone needs the pre-push hook switched on.
    if grep -Eq '(^|[^[:alnum:]_-])git([[:space:]].*)?[[:space:]]push([[:space:]]|$)' <<<"$cmd"; then
      while read -r d; do
        guarded "$d" || continue
        [ "$(git -C "$d" config core.hooksPath)" = .githooks ] ||
          deny "Push blocked: the review guard isn't switched on in $d. Run scripts/install-hooks.sh there first."
      done < <(candidates)
    fi
    # gh pr merge N: the PR's head must be the reviewed commit.
    if grep -Eq '(^|[^[:alnum:]_-])gh[[:space:]]+pr[[:space:]]+merge' <<<"$cmd"; then
      pr=$(sed -nE 's/.*gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+#?([0-9]+)([[:space:]]|$|[;&|]).*/\1/p' <<<"$cmd")
      d=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)
      if [ -n "$d" ] && guarded "$d"; then
        [ -n "$pr" ] || deny "Merge blocked: write the PR number right after 'gh pr merge' so its head can be checked for a code review."
        check_pr "$d" "$pr"
      fi
    fi
    ;;
  mcp__*github*)
    owner=$(jq -r '.tool_input.owner // ""' <<<"$input")
    repo=$(jq -r '.tool_input.repo // ""' <<<"$input")
    d=$(clone_of "$owner" "$repo" || true)
    # Only repositories that carry the rule, as far as a local clone shows.
    if [ -z "$d" ]; then
      case $tool in
        *__merge_pull_request|*__enable_pr_auto_merge)
          deny "Merge blocked: no local clone of $owner/$repo here to check its code review. Clone it, or merge from the repository's own session." ;;
      esac
      exit 0
    fi
    guarded "$d" || exit 0
    case $tool in
      *__merge_pull_request)
        check_pr "$d" "$(jq -r '.tool_input.pullNumber // .tool_input.pull_number // ""' <<<"$input")" ;;
      *__enable_pr_auto_merge)
        deny "Auto-merge is blocked: the PR would merge later without a check that its final commit was reviewed. Merge it once it's reviewed instead." ;;
      *__push_files|*__create_or_update_file|*__delete_file)
        branch=$(jq -r '.tool_input.branch // "main"' <<<"$input")
        [ "$branch" = main ] && deny "Committing straight to main through GitHub is blocked. Commit to a branch, get it reviewed, then merge." ;;
    esac
    ;;
esac
exit 0
