# glowscroll.lixlink.com — rules for agents

Static site for the GlowScroll app. Plain HTML/CSS, GitHub Pages from `main`: **every push to `main` publishes the live site.** See `README.md` for structure and checks.

# Code review before merges (always)

Every merge into `main` must be preceded by the `/code-review` skill — run `/code-review high` on the branch against `main` (or the whole branch while `main` doesn't exist yet). Fix each finding, or record why it isn't a bug (in the commit message or the PR). Then check every internal link, image and `#anchor` (README → Checks).

This is enforced: the PreToolUse hook in `.claude/settings.json` (`.claude/hooks/require-code-review.sh`) blocks `git merge` on `main`, `git push` to `main`, `gh pr merge` and the GitHub `merge_pull_request` tool unless the commit being merged is the one recorded by `scripts/mark-reviewed.sh`. Run that script only after the review on the final commit (fixes committed, checks green). Any new commit after it needs a new review. Never bypass the hook or write the mark by hand.

# Content

Every claim must match what the app (`bitPimps/glowscroll`) actually does. Never advertise unshipped features. The share-link page (`/s`, later) must not load Google Tag Manager.
