# glowscroll.lixlink.com — rules for agents

Static site for the GlowScroll app. Plain HTML/CSS, GitHub Pages from `main`: **every push to `main` publishes the live site.** See `README.md` for structure and checks.

# Code review before merges (always)

Same rule as the app repo (`bitPimps/glowscroll`, `AGENTS.md`) and ThymeIt's site: work on a branch and run `/code-review high` on it against `main` before pushing to `main` or opening a PR into it. Fix each finding, or record why it isn't a bug in the commit message or the PR. Re-run the review only when a fix changes more than the finding it answers.

CI (`.github/workflows/check.yml`) checks every internal link, image and `#anchor`, and the GTM container, on each PR and push to `main`. Don't merge while it's red.

# Content

Every claim must match what the app (`bitPimps/glowscroll`) actually does. Never advertise unshipped features. The share-link page (`/s`, later) must not load Google Tag Manager.

When an app feature ships or changes, update the matching pages here in the same piece of work. The app repo's `docs/07-roadmap-and-delivery.md` → "Keeping the site in sync" has the feature → site map and a sync log of site updates still owed. Clear an entry there once it's done here.
