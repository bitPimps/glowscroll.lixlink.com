# glowscroll.lixlink.com — rules for agents

Static site for the GlowScroll app. Plain HTML/CSS, GitHub Pages from `main`: **every push to `main` publishes the live site.** See `README.md` for structure and checks.

# Code review before merges (always)

Every merge into `main` must be preceded by the `/code-review` skill — run `/code-review high` on the branch against `main` (or the whole branch while `main` doesn't exist yet). Fix each finding, or record why it isn't a bug (in the commit message or the PR). Then check every internal link, image and `#anchor` (README → Checks).

This is enforced in two layers:

- **`.githooks/pre-push`** (git) refuses any push that updates `main` on the remote, however the push is spelled, unless the commit is the one `scripts/mark-reviewed.sh` recorded. It's switched on by `git config core.hooksPath .githooks`, which `scripts/install-hooks.sh` and the SessionStart hook in `.claude/settings.json` set.
- **`.claude/hooks/require-code-review.sh`** (Claude Code PreToolUse) keeps that on: it blocks `--no-verify`, changing `core.hooksPath`, and pushing while the guard is off. It also guards the paths around git: `gh pr merge N` and the GitHub tools' pull-request merge are checked against the PR's head commit on GitHub; committing straight to `main` through the GitHub tools or API (`gh api`, `curl`) and enabling auto-merge are refused. Writing the review mark by hand is refused, and changing the guard's own files (`.githooks/`, the hook, `.claude/settings.json`, the scripts) asks the user first.

Run `scripts/mark-reviewed.sh` only after the review on the final commit (fixes committed, the internal link check (README → Checks) green). Any new commit after it needs a new review. Never bypass the guard or write the mark by hand.

# Content

Every claim must match what the app (`bitPimps/glowscroll`) actually does. Never advertise unshipped features. The share-link page (`/s`, later) must not load Google Tag Manager.
