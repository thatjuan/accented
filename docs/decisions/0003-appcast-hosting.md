# ADR 0003 — Hosting the Sparkle appcast + binaries over HTTPS

- **Status:** Accepted (spec; hosting not yet stood up)
- **Date:** 2026-08-14
- **Part of:** issue **#9**
- **Port of:** diarc `docs/decisions/0004-appcast-hosting.md`
- **Delta from diarc:** domain is `accented.app`; R2 bucket is `accented-releases`;
  Worker is `accented-web`; no marketing site, no Amplitude, no feedback intake.
  `release.sh` uses `SPARKLE_ED_KEY_FILE`. Custom-domain routes in `web/wrangler.toml`
  stay commented until the zone exists.

## Context

Sparkle clients poll `appcast.xml` at the frozen `SUFeedURL`, then download the enclosure
it points to. The classic failure modes are an **over-cached appcast** (clients silently
miss releases) and a **feed that points at a not-yet-live enclosure** (updates break for
everyone polling in the gap). This ADR pins the URL layout, headers, and publish order.

## What `release.sh` produces

Writes into `${REPO_ROOT}/release-archives/` (gitignored, persistent across runs):

- `appcast.xml` — EdDSA-signed feed, regenerated over every `.zip` in the folder.
- `Accented-<SHORT>-<BUILD>.zip` — notarized Sparkle enclosure, **named by build number**.
  Marketing-version-only names collide across builds and corrupt the feed.
- `Accented-<SHORT>-<BUILD>.html` — optional release notes (`sparkle:releaseNotesLink`).
- `Accented-<SHORT>-<BUILD>.dmg` — human download; **not** an appcast enclosure.

`generate_appcast` is fed a **zip-only hardlink view** (`--maximum-deltas 0`). Feeding the
DMG trips Sparkle error 1002 (duplicate updates sharing a `CFBundleVersion`).

## Decision — URL layout

| Purpose | URL |
|---|---|
| `SUFeedURL` | `https://accented.app/appcast.xml` |
| Enclosure / notes prefix | `https://accented.app/releases/` |
| First-time human download | `https://accented.app/download` → 302 to the current DMG |

`SUFeedURL` and the enclosure prefix are independent. Both HTTPS and stable. The Worker
can 302 `/appcast.xml` via `APPCAST_REDIRECT_URL` without reshipping the app.

## Decision — Content-Type and cache headers

Sparkle requires HTTPS + ATS; the table is hosting best practice, not a Sparkle mandate.

| Artifact | `Content-Type` | `Cache-Control` |
|---|---|---|
| `appcast.xml` | `application/xml` | `public, max-age=300, must-revalidate` |
| `Accented-*.zip` | `application/zip` | `public, max-age=31536000, immutable` |
| `Accented-*.dmg` | `application/x-apple-diskimage` | `public, max-age=31536000, immutable` |
| `Accented-*.html` | `text/html; charset=utf-8` | `public, max-age=300, must-revalidate` |

The `SUFeedURL` redirect must itself not be cached longer than the appcast, and must stay
HTTPS end-to-end. The host must serve a correct `Content-Length` (Sparkle checks it).

Implemented in `web/src/index.ts` (R2 does not set these per object). Range / ETag /
`If-None-Match` are handled there too.

## Decision — Archives retention + publish procedure

`release-archives/` is gitignored, so it is **not** the durable record. `generate_appcast`
regenerates the feed from whatever zips are in the folder; a clean machine emits a
single-entry feed that, on upload, **drops every prior version**.

**The host is the source of truth; pull-before-regenerate.**

```
1. On a new machine (or after a cleanup):
     cd web && npm run sync          # publish.mjs pull → release-archives/

2. RELEASE_VERSION=0.1.1 SPARKLE_ED_KEY_FILE=~/accented-sparkle-ed25519-private.key \
     NOTARY_KEYCHAIN_PROFILE=… ./Scripts/release.sh
   Bumps CFBundleVersion from committed HEAD (failed runs cannot double-bump),
   notarizes, writes Accented-<v>-<build>.zip, regenerates appcast.xml.

3. release.sh uploads enclosure + DMG FIRST, appcast LAST, then deploys the Worker
   with DOWNLOAD_URL pointed at the new DMG.

4. Verify (checklist below).

5. The version-bump commit is mandatory — the next run reads HEAD for the baseline:
     chore: release 0.1.1 (build N)
```

`SKIP_PUBLISH=1` stops after local artifacts. Then `cd web && npm run publish:r2`.

Never overwrite a published `Accented-<short>-<build>.zip` — its EdDSA signature and
length are pinned in the feed.

## Verification checklist

- [ ] `curl -sI https://accented.app/appcast.xml` → 200, `application/xml`, short/revalidate
- [ ] `curl -sI https://accented.app/releases/Accented-<short>-<build>.zip` → 200, `application/zip`,
  immutable, correct `Content-Length`
- [ ] Download the zip; `codesign --verify --strict --verbose=2` (no `--deep` on **sign**)
  + `spctl --assess --type execute` pass after notarization
- [ ] A prior-version client validates the EdDSA signature and self-updates
      (0.1.0 → 0.1.1 acceptance; needs the real key + live host)

## Consequences

- **Appcast cache** is the freeze-into-prod footgun: always short TTL + revalidate.
- **Upload order:** archives before appcast.
- **Immutable archives:** build-number-keyed names; never overwrite.
- **Hosting standup** (`web/DEPLOY.md`) is still on the maintainer: zone, R2 bucket,
  uncomment custom-domain routes, generate the dedicated key (ADR 0002).
