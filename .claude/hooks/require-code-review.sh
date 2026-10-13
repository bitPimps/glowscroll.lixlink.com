#!/usr/bin/env bash
# Claude Code PreToolUse hook. The real gate is the git pre-push hook
# (.githooks/pre-push), which sees exactly which refs a push updates. This
# hook keeps that gate switched on and unbypassed, and guards the ways to
# change main that don't go through git push: merging a pull request,
# committing through the GitHub tools or API, and editing the guard itself.
# See AGENTS.md.
set -uo pipefail

input=$(cat)

decide() { # $1 deny|ask, $2 reason
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg d "$1" --arg r "$2" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
    exit 0
  fi
  echo "$2" >&2
  exit 2
}
deny() { decide deny "$1"; }
ask() { decide ask "$1"; }

if ! command -v jq >/dev/null 2>&1; then
  grep -Eiq 'git[[:space:]][^"]*push|gh[[:space:]]+(pr[[:space:]]+merge|api)|merge_pull_request|push_files|create_or_update_file|delete_file|auto_merge|core\.hookspath|code-review-ok|\.githooks/|require-code-review' <<<"$input" &&
    deny "The merge guard needs jq, so pushes, merges and guard changes are blocked until jq is installed."
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

GUARD_FILES='\.githooks/|require-code-review\.sh|mark-reviewed\.sh|install-hooks\.sh|\.claude/settings(\.local)?\.json'

# The folder a git or gh command runs in: git -C DIR, else a cd/pushd DIR in the command, else the cwd.
run_dir() {
  local dir
  dir=$(grep -Eo 'git[[:space:]]+-C[[:space:]]+[^[:space:];&|]+' <<<"$cmd" | tail -1 | awk '{print $3}')
  [ -n "$dir" ] || dir=$(grep -Eo '(^|[;&|(][[:space:]]*)(cd|pushd)[[:space:]]+[^[:space:];&|)]+' <<<"$cmd" | tail -1 | awk '{print $NF}')
  dir=$(tr -d "\"'{}" <<<"${dir:-$cwd}")
  dir=${dir//\$CLAUDE_PROJECT_DIR/${CLAUDE_PROJECT_DIR:-$cwd}}
  dir=${dir//\$HOME/$HOME}
  dir=${dir//\$PWD/$cwd}
  case $dir in *'$'*) dir=$cwd ;; esac # another variable: can't tell, use the cwd
  case $dir in /*) ;; "~"*) dir="$HOME${dir#\~}" ;; *) dir="$cwd/$dir" ;; esac
  echo "$dir"
}

case $tool in
  Bash)
    cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
    # The review mark is written only by scripts/mark-reviewed.sh, whose command line doesn't name it.
    grep -q 'code-review-ok' <<<"$cmd" &&
      deny "The review mark is written only by scripts/mark-reviewed.sh, after a review (AGENTS.md)."
    # Switching the git hooks off. Every core.hooksPath in the command must set .githooks or only read it.
    # git config keys aren't case-sensitive.
    all=$(grep -Eio 'core\.hookspath' <<<"$cmd" | wc -l)
    ok=$(grep -Eio "core\.hookspath([[:space:]]*=[[:space:]]*|[[:space:]]+)[\"']?\.githooks/?[\"']?([[:space:]]|\$|[;&|)])|core\.hookspath[[:space:]]*(\$|[;&|)])" <<<"$cmd" | wc -l)
    if [ "$all" -gt "$ok" ] || { [ "$all" -gt 0 ] && grep -Eq -- '--(unset|unset-all|remove-section|rename-section|replace-all|edit)([[:space:]]|$)' <<<"$cmd"; }; then
      deny "Changing core.hooksPath away from .githooks is blocked: it switches off the review guard."
    fi
    # git takes any unique prefix of a long option, so --no-veri is --no-verify.
    if grep -Eq '(^|[^[:alnum:]_-])git([[:space:]][^;&|]*)?[[:space:]]push([[:space:]][^;&|]*)?[[:space:]]--no-v' <<<"$cmd"; then
      deny "git push --no-verify is blocked: it skips the review guard."
    fi
    # A push needs the pre-push hook switched on in the clone it runs in. That
    # folder can be guessed wrong, so it's switched on in every guarded clone
    # nearby (what scripts/install-hooks.sh does).
    if grep -Eq '(^|[^[:alnum:]_-])git([[:space:]].*)?[[:space:]]push([[:space:]]|$)' <<<"$cmd"; then
      dir=$(run_dir)
      git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 ||
        deny "Push blocked: $dir isn't a clone yet, so the review guard can't be checked. Clone first, run scripts/install-hooks.sh there, then push."
      while read -r d; do
        guarded "$d" || continue
        [ "$(git -C "$d" config core.hooksPath)" = .githooks ] ||
          git -C "$d" config core.hooksPath .githooks ||
          deny "Push blocked: couldn't switch the review guard on in $d. Run scripts/install-hooks.sh there first."
      done < <({ echo "$dir"; candidates; } | awk '!seen[$0]++')
    fi
    # GitHub's REST or GraphQL API: merging a pull request or writing a branch or file outside git.
    if grep -Eq '(^|[^[:alnum:]_-])(gh[[:space:]]+api|curl)([[:space:]]|$)' <<<"$cmd"; then
      if grep -Eq 'mergePullRequest|enablePullRequestAutoMerge|createCommitOnBranch|updateRef|createRef|deleteRef' <<<"$cmd" ||
        { grep -Eq 'pulls/[0-9]+/merge|/merges([^[:alnum:]]|$)|git/refs|/contents/' <<<"$cmd" &&
          grep -Eq '(^|[[:space:]])(-X|--method|--request|-f|-F|--field|--raw-field|--input|-d|--data[[:alnum:]-]*)([[:space:]=]|$)|(^|[[:space:]])-X[A-Z]' <<<"$cmd"; }; then
        deny "Changing a repository through the GitHub API is blocked: it skips the review guard. Push a branch and merge it with 'gh pr merge N' once it's reviewed."
      fi
    fi
    # gh pr merge N: the PR's head must be the reviewed commit.
    if grep -Eq '(^|[^[:alnum:]_-])gh[[:space:]]+pr[[:space:]]+merge' <<<"$cmd"; then
      grep -Eq -- '--auto([[:space:]]|$)' <<<"$cmd" &&
        deny "Auto-merge is blocked: the PR would merge later without a check that its final commit was reviewed. Merge it once it's reviewed instead."
      pr=$(sed -nE 's/.*gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+#?([0-9]+)([[:space:]]|$|[;&|]).*/\1/p' <<<"$cmd")
      target=$(grep -Eo -- '(-R|--repo|GH_REPO)[[:space:]=]+[^[:space:];&|]+' <<<"$cmd" | tail -1 | sed -E 's/^(-R|--repo|GH_REPO)[[:space:]=]+//' | tr -d "\"'")
      [ -n "$target" ] || target=${GH_REPO:-}
      # A PR URL names both the repository and the number.
      url=$(grep -Eo 'github\.com/[^/[:space:]]+/[^/[:space:]]+/pull/[0-9]+' <<<"$cmd" | tail -1)
      if [ -n "$url" ]; then
        pr=${url##*/}
        target=$(cut -d/ -f2-3 <<<"$url")
      fi
      if [ -n "$target" ]; then
        target=${target##*github.com/}
        d=$(clone_of "${target%%/*}" "${target#*/}" || true)
        [ -n "$d" ] || deny "Merge blocked: no local clone of $target here to check its code review. Merge from inside a clone of it."
      else
        d=$(git -C "$(run_dir)" rev-parse --show-toplevel 2>/dev/null) ||
          deny "Merge blocked: run 'gh pr merge' inside a clone of the repository, so its code review can be checked."
      fi
      if guarded "$d"; then
        [ -n "$pr" ] || deny "Merge blocked: write the PR number right after 'gh pr merge' so its head can be checked for a code review."
        check_pr "$d" "$pr"
      fi
    fi
    # Last, after every deny above: changing the guard's own files needs the user's OK.
    if grep -Eq "$GUARD_FILES" <<<"$cmd" &&
      grep -Eq '>|(^|[^[:alnum:]_-])(rm|mv|cp|tee|chmod|truncate|ln)[[:space:]]|sed[[:space:]]+(-[[:alnum:]]*[[:space:]]+)*-i|git[[:space:]]+(checkout|restore|rm|mv)' <<<"$cmd"; then
      ask "This command may change the review guard's own files (AGENTS.md). Allow it?"
    fi
    ;;
  Write | Edit | MultiEdit | NotebookEdit)
    path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")
    case $path in
      *code-review-ok) deny "The review mark is written only by scripts/mark-reviewed.sh, after a review (AGENTS.md)." ;;
    esac
    grep -Eq "$GUARD_FILES" <<<"$path" && ask "$path is part of the review guard (AGENTS.md). Allow this change?"
    ;;
  mcp__*github*)
    owner=$(jq -r '.tool_input.owner // ""' <<<"$input")
    repo=$(jq -r '.tool_input.repo // ""' <<<"$input")
    d=$(clone_of "$owner" "$repo" || true)
    # Without a local clone there's no telling whether the repository carries the rule: refuse.
    if [ -z "$d" ] || guarded "$d"; then
      case $tool in
        *__merge_pull_request)
          [ -n "$d" ] || deny "Merge blocked: no local clone of $owner/$repo here to check its code review. Clone it, or merge from the repository's own session."
          check_pr "$d" "$(jq -r '.tool_input.pullNumber // .tool_input.pull_number // ""' <<<"$input")" ;;
        *__enable_pr_auto_merge)
          deny "Auto-merge is blocked: the PR would merge later without a check that its final commit was reviewed. Merge it once it's reviewed instead." ;;
        *__push_files | *__create_or_update_file | *__delete_file)
          branch=$(jq -r '.tool_input.branch // "main"' <<<"$input")
          [ "$branch" = main ] && deny "Committing straight to main through GitHub is blocked. Commit to a branch, get it reviewed, then merge." ;;
      esac
    fi
    ;;
esac
exit 0
