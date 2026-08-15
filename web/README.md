# accented.app — marketing site + Sparkle host

One-page site in `public/` plus a Worker that fronts R2 for the Sparkle feed
and release binaries. Copy: `COPY.md`. Design: `DESIGN.md`.

## Frozen contracts (do not change after first ship)

| Thing | Value |
|---|---|
| `SUFeedURL` (baked into every shipped build) | `https://accented.app/appcast.xml` |
| Enclosure URL prefix (`generate_appcast --download-url-prefix`) | `https://accented.app/releases/` |
| Release-notes prefix | `https://accented.app/releases/` |
| Human download CTA | `https://accented.app/download` → 302 to the current DMG |

`appcast.xml` is served with a short, revalidating cache — never immutable. Hard-caching
the appcast silently strands clients on an old feed. Enclosures use versioned filenames
and are cached `immutable` forever.

See `DEPLOY.md` for one-time standup, and `docs/decisions/0002-sparkle-auto-updates.md` +
`docs/decisions/0003-appcast-hosting.md` for the key and hosting contracts.

## Layout

```
web/
  wrangler.toml          Worker + R2 binding (RELEASES → accented-releases)
  src/index.ts           /healthz, /appcast.xml, /releases/*, /download
  public/                one-page site + 404 + OG/favicon + /llms.txt + /index.md
  COPY.md                locked marketing copy
  DESIGN.md              direction, tokens, image prompts
  scripts/publish.mjs    pull-before-regenerate + ordered upload to R2
  .dev.vars.example      publish-pipeline R2 credentials
```

## Local

```bash
cd web
npm install
npm run dev
curl -sI localhost:8787/healthz
```

Seed a local R2 object to exercise the feed route:

```bash
npx wrangler r2 object put accented-releases/appcast.xml --file ../release-archives/appcast.xml --local
curl -sI localhost:8787/appcast.xml
```
