#!/usr/bin/env bash
#
# release.sh — full release. Bumps the version, builds + signs + notarizes (via notarize.sh),
# cuts the Sparkle enclosure + an EdDSA-signed appcast, publishes to R2, verifies the live
# feed, and commits the version bump.
#
# Pipeline:
#   1. bump CFBundleVersion (+1 from committed HEAD) + CFBundleShortVersionString (= RELEASE_VERSION)
#   2. notarize.sh  → dist/Accented.app + ~/Downloads/Accented.dmg
#   3. cut release-archives/Accented-<v>-<build>.zip
#   4. generate_appcast over a zip-only hardlink view (--maximum-deltas 0)
#   5. upload enclosure + DMG FIRST, appcast LAST
#   6. point /download at the new DMG + deploy the Worker
#   7. verify the live appcast/enclosure over HTTPS
#   8. commit "chore: release X.Y.Z (build N)"
#
# For a local signed+notarized build with no publish, use notarize.sh directly.
#
# Required:
#   RELEASE_VERSION      marketing version, e.g. 0.1.1
#
# Env knobs:
#   OUTPUT_DIR, DOWNLOAD_URL_PREFIX, RELEASE_NOTES_URL_PREFIX, SPARKLE_BIN_DIR
#   SPARKLE_ED_KEY_FILE  private key file (preferred — do not use diarc's keychain default)
#   On a new machine, `cd web && npm run sync` first so generate_appcast sees full history.
#   SKIP_PUBLISH=1       stop after local artifacts + appcast
#   SKIP_DEPLOY=1        upload but don't deploy the Worker
#   SKIP_COMMIT=1        print the commit command instead of committing
#   ALLOW_DIRTY_PLIST=1  skip the clean-plist preflight
#   SKIP_DMG_NOTARIZE=1  forwarded to notarize.sh

set -euo pipefail

readonly APP_NAME="Accented"
readonly R2_BUCKET="accented-releases"
readonly CF_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly WEB_DIR="${REPO_ROOT}/web"
readonly INFO_PLIST="${REPO_ROOT}/Sources/${APP_NAME}/Info.plist"
readonly ARCHIVES_DIR="${REPO_ROOT}/release-archives"
readonly OUT_DIR="${OUTPUT_DIR:-${HOME}/Downloads}"
readonly DMG_PATH="${OUT_DIR}/${APP_NAME}.dmg"
readonly DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://accented.app/releases/}"
readonly RELEASE_NOTES_URL_PREFIX="${RELEASE_NOTES_URL_PREFIX:-https://accented.app/releases/}"

wrangler_oauth() {
    ( cd "${WEB_DIR}" && CLOUDFLARE_ACCOUNT_ID="${CF_ACCOUNT_ID}" env -u CLOUDFLARE_API_TOKEN npx wrangler "$@" )
}

command -v git >/dev/null || { echo "ERROR: git not found." >&2; exit 1; }
[[ -n "${RELEASE_VERSION:-}" ]] || { echo "ERROR: set RELEASE_VERSION=x.y.z" >&2; exit 1; }

if [[ "${ALLOW_DIRTY_PLIST:-0}" != "1" ]] && ! git -C "${REPO_ROOT}" diff --quiet -- "${INFO_PLIST}"; then
    echo "ERROR: ${INFO_PLIST} has uncommitted changes. Commit/stash them, or set ALLOW_DIRTY_PLIST=1." >&2
    exit 1
fi

if [[ "${SKIP_PUBLISH:-0}" != "1" ]]; then
    command -v node >/dev/null || { echo "ERROR: node not found (needed for npx wrangler)." >&2; exit 1; }
    command -v curl >/dev/null || { echo "ERROR: curl not found." >&2; exit 1; }
    [[ -d "${WEB_DIR}/node_modules" ]] || { echo "ERROR: ${WEB_DIR}/node_modules missing — run 'cd web && npm install' first." >&2; exit 1; }
fi

# --- 1. Bump version -------------------------------------------------------------------------
BASELINE_BUILD="$(git -C "${REPO_ROOT}" show "HEAD:Sources/${APP_NAME}/Info.plist" \
    | plutil -extract CFBundleVersion raw -o - -)"
[[ "${BASELINE_BUILD}" =~ ^[0-9]+$ ]] || { echo "ERROR: committed CFBundleVersion '${BASELINE_BUILD}' is not an integer." >&2; exit 1; }
readonly NEW_BUILD=$(( BASELINE_BUILD + 1 ))

echo "==> Bumping version: build ${BASELINE_BUILD} -> ${NEW_BUILD}, marketing ${RELEASE_VERSION}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW_BUILD}" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${RELEASE_VERSION}" "${INFO_PLIST}"

# --- 2. Build + sign + notarize --------------------------------------------------------------
echo "==> Build + sign + notarize…"
OUTPUT_DIR="${OUT_DIR}" "${SCRIPT_DIR}/notarize.sh"
readonly APP_BUNDLE="${REPO_ROOT}/dist/${APP_NAME}.app"
[[ -d "${APP_BUNDLE}" ]] || { echo "ERROR: ${APP_BUNDLE} missing after notarize.sh" >&2; exit 1; }
[[ -f "${DMG_PATH}" ]]   || { echo "ERROR: ${DMG_PATH} missing after notarize.sh" >&2; exit 1; }

# --- 3. Sparkle enclosure + staged DMG -------------------------------------------------------
mkdir -p "${ARCHIVES_DIR}"
readonly ENCLOSURE_ZIP="${ARCHIVES_DIR}/${APP_NAME}-${RELEASE_VERSION}-${NEW_BUILD}.zip"
readonly STAGED_DMG="${ARCHIVES_DIR}/${APP_NAME}-${RELEASE_VERSION}-${NEW_BUILD}.dmg"
echo "==> Writing Sparkle enclosure ${ENCLOSURE_ZIP}…"
rm -f "${ENCLOSURE_ZIP}"
ditto -c -k --keepParent "${APP_BUNDLE}" "${ENCLOSURE_ZIP}"
echo "==> Staging DMG ${STAGED_DMG}…"
cp "${DMG_PATH}" "${STAGED_DMG}"

# --- 4. generate_appcast (zip-only view) -----------------------------------------------------
GEN_APPCAST="${SPARKLE_BIN_DIR:+${SPARKLE_BIN_DIR}/generate_appcast}"
if [[ -z "${GEN_APPCAST}" || ! -x "${GEN_APPCAST}" ]]; then
    GEN_APPCAST="$(find "${REPO_ROOT}/.build" -type f -path '*/Sparkle/bin/generate_appcast' 2>/dev/null | head -n1)"
fi
[[ -x "${GEN_APPCAST}" ]] || { echo "ERROR: generate_appcast not found. Set SPARKLE_BIN_DIR." >&2; exit 1; }

echo "==> Generating signed appcast over the .zip enclosures in ${ARCHIVES_DIR}…"
APPCAST_SRC="$(mktemp -d "${ARCHIVES_DIR}/.appcast-src.XXXXXX")"
trap 'rm -rf "${APPCAST_SRC}"' EXIT
for z in "${ARCHIVES_DIR}"/*.zip; do [[ -e "${z}" ]] && ln "${z}" "${APPCAST_SRC}/$(basename "${z}")"; done
GEN_ARGS=(
    --maximum-deltas 0
    -o "${ARCHIVES_DIR}/appcast.xml"
    --download-url-prefix "${DOWNLOAD_URL_PREFIX}"
    --release-notes-url-prefix "${RELEASE_NOTES_URL_PREFIX}"
)
if [[ -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
    GEN_ARGS+=(--ed-key-file "${SPARKLE_ED_KEY_FILE}")
fi
"${GEN_APPCAST}" "${GEN_ARGS[@]}" "${APPCAST_SRC}"
rm -rf "${APPCAST_SRC}"; trap - EXIT

if [[ "${SKIP_PUBLISH:-0}" == "1" ]]; then
    echo ""
    echo "==> SKIP_PUBLISH=1 — local artifacts ready, nothing uploaded:"
    echo "Enclosure: ${ENCLOSURE_ZIP}"
    echo "DMG:       ${STAGED_DMG}  (and ${DMG_PATH})"
    echo "Appcast:   ${ARCHIVES_DIR}/appcast.xml"
    exit 0
fi

# --- 5. Upload to R2 (enclosure + DMG FIRST, appcast LAST) -----------------------------------
echo "==> Uploading to R2 bucket ${R2_BUCKET}…"
wrangler_oauth r2 object put "${R2_BUCKET}/releases/$(basename "${ENCLOSURE_ZIP}")" \
    --file "${ENCLOSURE_ZIP}" --content-type application/zip --remote
wrangler_oauth r2 object put "${R2_BUCKET}/releases/$(basename "${STAGED_DMG}")" \
    --file "${STAGED_DMG}" --content-type application/x-apple-diskimage --remote
wrangler_oauth r2 object put "${R2_BUCKET}/appcast.xml" \
    --file "${ARCHIVES_DIR}/appcast.xml" --content-type application/xml --remote

# --- 6. Point /download + deploy -------------------------------------------------------------
readonly DOWNLOAD_PATH="/releases/${APP_NAME}-${RELEASE_VERSION}-${NEW_BUILD}.dmg"
echo "==> Setting wrangler.toml DOWNLOAD_URL = ${DOWNLOAD_PATH}…"
/usr/bin/sed -i '' -E "s|^DOWNLOAD_URL = .*|DOWNLOAD_URL = \"${DOWNLOAD_PATH}\"|" "${WEB_DIR}/wrangler.toml"
if [[ "${SKIP_DEPLOY:-0}" == "1" ]]; then
    echo "==> SKIP_DEPLOY=1 — not deploying the Worker."
else
    echo "==> Deploying Worker…"
    wrangler_oauth deploy
fi

# --- 7. Verify live feed ---------------------------------------------------------------------
echo "==> Verifying live feed…"
APPCAST_URL="${DOWNLOAD_URL_PREFIX%releases/}appcast.xml"
ENCLOSURE_URL="${DOWNLOAD_URL_PREFIX}${APP_NAME}-${RELEASE_VERSION}-${NEW_BUILD}.zip"
echo "--- ${APPCAST_URL}";   curl -fsSI "${APPCAST_URL}"   | grep -iE "^HTTP|content-type" || echo "WARN: appcast not reachable"
echo "--- ${ENCLOSURE_URL}"; curl -fsSI "${ENCLOSURE_URL}" | grep -iE "^HTTP|content-length" || echo "WARN: enclosure not reachable"

# --- 8. Commit -------------------------------------------------------------------------------
if [[ "${SKIP_COMMIT:-0}" == "1" ]]; then
    echo "==> SKIP_COMMIT=1 — commit yourself so the next run reads the right baseline:"
    echo "    git -C \"${REPO_ROOT}\" add Sources/${APP_NAME}/Info.plist web/wrangler.toml && git -C \"${REPO_ROOT}\" commit -m \"chore: release ${RELEASE_VERSION} (build ${NEW_BUILD})\""
else
    echo "==> Committing version bump + DOWNLOAD_URL…"
    git -C "${REPO_ROOT}" add "Sources/${APP_NAME}/Info.plist" "web/wrangler.toml"
    git -C "${REPO_ROOT}" commit -m "chore: release ${RELEASE_VERSION} (build ${NEW_BUILD})"
fi

echo ""
echo "==> Released ${RELEASE_VERSION} (build ${NEW_BUILD})."
echo "Human DMG:  ${DMG_PATH}"
echo "Enclosure:  ${ENCLOSURE_ZIP}"
echo "Appcast:    ${ARCHIVES_DIR}/appcast.xml"
echo "Push the bump when ready:  git -C \"${REPO_ROOT}\" push"
