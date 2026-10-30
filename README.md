# glowscroll.lixlink.com

Marketing and support site for **GlowScroll: LED Banner & Sign**, published by THE LIX GROUP LLC. The app lives in [`bitPimps/glowscroll`](https://github.com/bitPimps/glowscroll). Static site, no build step, no framework — built the same way as `steady.lixlink.com`.

## Pages

- `index.html`: landing page: what GlowScroll does, features, privacy, pricing, download (Google Play badge; iPhone **"coming soon"** until it's in the App Store)
- `faq.html`: searchable Help Center. Section ids (`#getting-started`, `#showing-signs`, `#saved-banners`, `#privacy-data`, `#backup-restore`, `#premium`, `#troubleshooting`) are stable so in-app help can link to them
- `privacy.html`: privacy policy (App Store and Google Play require its URL)
- `delete-data.html`: how to delete on-device data and purchase records
- `404.html`: not-found page
- `llms.txt`, `robots.txt`, `sitemap.xml`: discovery files. Update `llms.txt` and the sitemap when pages, features or pricing change. JSON-LD lives in each page's `<head>`; the FAQPage schema in `faq.html` must match the visible FAQ word for word.

## Structure

```
assets/css/style.css   shared stylesheet (dark only; tokens match the app's theme-colors.js)
assets/js/main.js      mobile nav toggle + FAQ search/filter (from Steady's site)
assets/img/            favicons, app icon, og-image.png (1200×630), LED sign images, store badges
.nojekyll              tells GitHub Pages not to run Jekyll (needed later for .well-known/)
```

The LED sign images and icons were drawn with the app's own LED shader and icon (`scripts/make-icons.mjs` in the app repo). Replace them with real screenshots once device builds exist.

## Deployment

GitHub Pages, **Settings → Pages → Deploy from a branch**: `main`, `/ (root)`. Every push to `main` publishes.

Custom domain (manual, account owner):
1. At the DNS provider for `lixlink.com`, add `CNAME glowscroll → bitpimps.github.io`.
2. In this repo's **Settings → Pages**, set the custom domain to `glowscroll.lixlink.com` (already in the `CNAME` file) and tick **Enforce HTTPS** once the certificate is issued.

## Analytics

Google Analytics 4 through Google Tag Manager, with GlowScroll's own container (`GTM-5RXX3PNS`). The GA4 tag is set up in that container, not in the HTML. The app itself has no analytics. The planned share-link page (`/s`, app 1.1) must **not** load GTM, because the banner text is in its URL.

## Code review before merging

Every change to `main` gets a `/code-review high` pass and lands through a PR, same rule as the app repo (see `AGENTS.md`).

## Checks

`.github/workflows/check.yml` runs [lychee](https://github.com/lycheeverse/lychee) on every PR and push to `main` and fails on a broken internal link, image or `#anchor`. It also checks that every page loads GlowScroll's GTM container (`GTM-5RXX3PNS`, script and noscript) and no other. Locally:

```
lychee --offline --root-dir "$PWD" --index-files index.html --include-fragments '*.html'
```

Dependabot opens a monthly PR to bump GitHub Actions versions.

## Keeping the site in sync

Every claim must match what the app actually does. When a feature ships or changes in the app, update the matching FAQ section (and its FAQPage JSON-LD), `llms.txt` and the home page. Never advertise unshipped features. The feature → site map and the sync log of updates still owed live in the app repo: `docs/07-roadmap-and-delivery.md` → "Keeping the site in sync".

**When the iPhone version ships:** add the App Store badge and link to `index.html` `#download`, put iCloud back next to Google Drive on the home page (backup card and pricing list), say export/import works between iPhone and Android again, update the Family Sharing answer in the FAQ, set `operatingSystem` to "iOS, Android" in the home page JSON-LD, and update `llms.txt`.

**Still to check:**
- Support mailbox `glowscroll-support@lixlink.com` exists
- "Any language, any emoji" claim verified on real phones
