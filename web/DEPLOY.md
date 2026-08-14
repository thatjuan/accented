# Deploy & domain standup (accented.app)

One-time Cloudflare setup to make the Worker live at `https://accented.app`. Everything here
is account-level and needs a Cloudflare login; nothing secret is committed.

`SUFeedURL` (`https://accented.app/appcast.xml`) freezes into every shipped build. Stand this
up before the first real release.

## 0. Prerequisites

- A Cloudflare account.
- `wrangler login` (interactive, browser) — or a `CLOUDFLARE_API_TOKEN` env var with
  Workers + R2 + DNS edit scope.
- The `accented.app` domain added as a **zone** in this Cloudflare account (Add Site → enter
  `accented.app` → set the registrar's nameservers to the ones Cloudflare assigns). TLS is
  Cloudflare **Universal SSL** (automatic once the zone is active).

## 1. R2 bucket

```bash
wrangler r2 bucket create accented-releases
```

## 2. Deploy the Worker

```bash
cd web
npm install
npm run deploy
```

`wrangler.toml` ships with `workers_dev = true` and the custom-domain routes **commented
out**, so the first deploy lands on `*.workers.dev` without needing the zone. After the
zone is active, uncomment the `[[routes]]` blocks for `accented.app` + `www.accented.app`
and deploy again. Wrangler then creates the proxied DNS records and Cloudflare issues the
TLS cert. HTTPS is end-to-end — required by Apple ATS and by Sparkle (a redirect to HTTP
fails silently on clients).

## 3. Keep `SUFeedURL` redirectable

`https://accented.app/appcast.xml` is frozen into every shipped build and can never change.
To move the appcast's physical location later **without reshipping the app**, set the
`APPCAST_REDIRECT_URL` var to an absolute `https://…` URL — the Worker then 302s `/appcast.xml`
there (with a short, non-pinned cache) instead of serving R2:

```bash
wrangler deploy --var APPCAST_REDIRECT_URL:https://new-host.example/appcast.xml
```

Leave it unset to serve the appcast straight from R2 (the default).

## 4. Publish pipeline credentials

Copy `.dev.vars.example` → `.dev.vars` and fill in an R2 API token scoped to
`accented-releases` (Object Read & Write). Used only by `scripts/publish.mjs`.

On a new machine, pull host history before the first `release.sh` so `generate_appcast`
does not overwrite the live feed with a single-entry appcast:

```bash
cd web && npm run sync
```

`Scripts/release.sh` uploads enclosure + DMG first, then `appcast.xml` last. Use
`SKIP_PUBLISH=1` to stop after local artifacts; then `npm run publish:r2`.

## 5. Verify live

```bash
curl -sI https://accented.app/healthz                     # 200
curl -sI https://accented.app/appcast.xml                 # 200, application/xml, short/no-cache, valid TLS
curl -sI https://accented.app/releases/Accented-<v>-<b>.zip  # 200, application/zip, immutable, Content-Length
curl -sI https://accented.app/download                    # 302 → current DMG
```

Confirm the redirect chain (if `APPCAST_REDIRECT_URL` is set) stays HTTPS end-to-end:

```bash
curl -sIL https://accented.app/appcast.xml | grep -i '^location\|^HTTP'
```

## Notes

- DNS/TLS/routes are managed by `wrangler deploy` from `wrangler.toml` once the custom-domain
  routes are uncommented — no manual dashboard DNS edits needed beyond adding the zone in step 0.
- No tokens in the repo.
