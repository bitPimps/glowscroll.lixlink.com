#!/usr/bin/env bash
# Records that /code-review was run on the current commit, which the
# .claude/hooks/require-code-review.sh hook requires before a merge into main.
# Run it only after the review's findings are fixed (or answered) and committed.
set -euo pipefail
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "Commit your changes first: the review mark is for a commit." >&2
  exit 1
fi
git rev-parse HEAD > "$(git rev-parse --absolute-git-dir)/code-review-ok"
echo "Marked $(git rev-parse --short HEAD) as reviewed."
