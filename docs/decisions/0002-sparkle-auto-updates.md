# ADR 0002 — Sparkle 2 auto-updates: EdDSA keys and the `SUFeedURL` contract

- **Status:** Accepted — key generated 2026-08-14 (`--account accented`); `SUPublicEDKey` baked in
- **Date:** 2026-08-14
- **Part of:** issue **#9**
- **Port of:** diarc `docs/decisions/0003-sparkle-auto-updates.md`
- **Delta from diarc:** Accented uses a **dedicated** keypair. Do **not** run bare
  `generate_keys` — that writes the default login-keychain item (service
  `https://sparkle-project.org`, account `ed25519`) that **diarc already owns**.
  Generate with `--account accented` and/or `--ed-key-file`. `release.sh` prefers
  `SPARKLE_ED_KEY_FILE`. Domain is `accented.app`.

## Context

Accented ships as a hand-assembled, notarized Developer-ID, non-sandboxed macOS app and
embeds Sparkle 2 so it can auto-update from a self-hosted appcast. Sparkle verifies
**each downloaded archive** with an Ed25519 signature that is **independent of, and
additional to,** Apple's code-signature / notarization:

- The **private key** signs the appcast enclosures at release time (`generate_appcast`).
- The **public key** (`SUPublicEDKey`) is baked into the app and verifies each download.

Both layers are required. This ADR records how Accented's keypair is generated without
colliding with diarc, the lost-key failure mode, and the four Sparkle keys in
`Sources/Accented/Info.plist`.

## Decision

1. **Dedicated keypair.** Generate with Sparkle's `generate_keys` using a non-default
   account and a file backup. Never reuse diarc's key. Never run `generate_keys` with no
   flags on a machine that also ships diarc.
2. **`release.sh` reads `SPARKLE_ED_KEY_FILE` when set** and passes `--ed-key-file`. That
   is the happy path. The keychain default is diarc's slot and must not be implied.
3. **Back up the private key the same day** with `generate_keys -x`. A lost key with no
   backup is unrecoverable and forces a rotation.
4. **`SUFeedURL` is `https://accented.app/appcast.xml`.** It freezes into every shipped
   binary. HTTPS, stable, redirectable (Worker `APPCAST_REDIRECT_URL`). Pick the domain
   before first ship — done here.
5. **`SUPublicEDKey` is `hJ08/m9H2qvxYurB+NwqOba3wE++9GhKNc7YI0MBrI0=`** (account
   `accented`, generated 2026-08-14). Private key lives in the login keychain and in
   `~/accented-sparkle-ed25519-private.key` (not in the repo).

## EdDSA key procedure (maintainer)

`generate_keys` lives next to the Sparkle framework:

```bash
SPARKLE_BIN_DIR="$(find .build -type f -path '*/Sparkle/bin/generate_keys' | head -n1 | xargs dirname)"
```

### Generate (once) — dedicated account, not the diarc default

```bash
"${SPARKLE_BIN_DIR}/generate_keys" --account accented
"${SPARKLE_BIN_DIR}/generate_keys" --account accented -x ~/accented-sparkle-ed25519-private.key
```

`--account accented` stores a **separate** keychain item (same service, different account)
so diarc's `ed25519` item is untouched.

Paste the printed public key into `Sources/Accented/Info.plist` as `SUPublicEDKey`.

Store the `-x` file in a password manager. Never commit it. `chmod 600`.

### How `release.sh` uses the key

```bash
SPARKLE_ED_KEY_FILE=~/accented-sparkle-ed25519-private.key \
  RELEASE_VERSION=0.1.1 ./Scripts/release.sh
```

That passes `--ed-key-file` to `generate_appcast`. Do **not** rely on the default keychain
lookup.

### Recover / move to a new machine

```bash
"${SPARKLE_BIN_DIR}/generate_keys" --account accented -f ~/accented-sparkle-ed25519-private.key
"${SPARKLE_BIN_DIR}/generate_keys" --account accented -p
# -p output must equal the SUPublicEDKey baked into Info.plist
```

### Lost-key failure mode

If the private key and the `-x` backup are both gone, existing clients will not accept
signatures from a new keypair. Recovery is a **key rotation**: ship a new Developer-ID
build (same identity `D6X5HPDXAG`, so TCC grants survive) carrying a new `SUPublicEDKey`,
signed onto the **old** still-signable feed. Painful. The same-day backup is the mitigation.

## `SUFeedURL` contract

- **Value:** `https://accented.app/appcast.xml`
- **Freeze:** old clients fetch whatever URL their build carried, forever. HTTPS; stable;
  redirectable (see ADR 0003). Never bake a CDN bucket URL or a host you might lose.
- **Distinct from enclosure URLs.** Those are `https://accented.app/releases/` via
  `generate_appcast --download-url-prefix`.

Safe to revise **until** the first Sparkle-enabled build ships. After that, only a
redirect (or a new major that nobody has yet) can move it.

## Info.plist keys

| Key | Value | Rationale |
|---|---|---|
| `SUEnableAutomaticChecks` | `<true/>` | Seeds default-on background checks. Settings toggle writes `SPUUpdater.automaticallyChecksForUpdates` (Sparkle's UserDefaults is the runtime store). |
| `SUFeedURL` | `https://accented.app/appcast.xml` | Frozen feed URL. |
| `SUPublicEDKey` | `hJ08/m9H2qvxYurB+NwqOba3wE++9GhKNc7YI0MBrI0=` | Public half of the `--account accented` keypair. |
| `SUScheduledCheckInterval` | `86400` | Daily. |

Sandboxed-only Sparkle keys are **not** added. Accented is not sandboxed.

## Consequences

- The public key is baked in. Signing a feed still needs `SPARKLE_ED_KEY_FILE` (or the
  `accented` keychain item) plus live hosting (ADR 0003).
- **Still on the maintainer:** put the `-x` backup in a password manager, then stand up
  `accented.app`.
- Do not run `generate_keys -f` (or bare `generate_keys`) against the default account on
  this machine. That is diarc's slot.
