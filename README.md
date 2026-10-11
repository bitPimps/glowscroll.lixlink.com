# glowscroll.lixlink.com

Marketing and support website for **GlowScroll – LED Banner & Scroller**, published by THE LIX GROUP LLC. The app lives in [`bitPimps/glowscroll`](https://github.com/bitPimps/glowscroll).

**Status:** planning. The site plan (pages, hosting, analytics rules) is in the app repo: [`docs/07-roadmap-and-delivery.md` → Website](https://github.com/bitPimps/glowscroll/blob/main/docs/07-roadmap-and-delivery.md#website-glowscrolllixlinkcom).

## How it works

- Plain static HTML/CSS, same approach as `steady.lixlink.com` and `thymeit.lixlink.com`.
- Hosted on **GitHub Pages** (Settings → Pages → Deploy from a branch: `main`, root). No build step.
- Custom domain `glowscroll.lixlink.com` via a `CNAME` file and a DNS `CNAME glowscroll → bitpimps.github.io`.
- **Google Analytics 4** on site pages — except the 1.1 share-link page (`/s`), which must load no analytics.

## Planned pages

| Page | Purpose |
|------|---------|
| `index.html` | Landing page, store badges |
| `privacy.html` | Privacy policy (required by both stores) |
| `faq.html` | Support / FAQ (store support URL) |
| `delete-data.html` | How to delete local data and backups |
| `404.html` | Not found |
| `s/index.html` (1.1) | Share-link preview, no analytics |
