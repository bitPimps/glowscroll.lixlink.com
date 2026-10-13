#!/usr/bin/env bash
# Turns on this repo's git hooks (.githooks/), including the pre-push guard
# that keeps unreviewed commits off main. Safe to run more than once.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git config core.hooksPath .githooks
echo "Git hooks enabled (.githooks)."
