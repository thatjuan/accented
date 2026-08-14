#!/usr/bin/env bash
#
# notarize.sh — build + Developer ID sign (via package.sh) + Apple-notarize + staple, producing a
# signed, NOTARIZED .app and .dmg stored LOCALLY. Nothing here touches the version, git, or the web:
# it is a pure local-artifact build. `release.sh` (arriving with #9) calls this and then publishes;
# run it directly when you just want a notarized build to hand-test or sideload.
#
# Output:
#   dist/Accented.app           — notarized + stapled (launches with zero Gatekeeper friction)
#   <OUTPUT_DIR>/Accented.dmg   — notarized + stapled DMG (default OUTPUT_DIR: ~/Downloads)
#
# Two notarization passes (app, then DMG): stapling embeds the ticket so the artifact passes
# Gatekeeper offline. A read-only DMG can't have the app inside it stapled after the fact, so the app
# is stapled BEFORE it goes into the DMG (pass 1); the DMG is then its own artifact that also gets a
# ticket (pass 2). Set SKIP_DMG_NOTARIZE=1 for app-only (one pass; the app still launches clean, only
# the .dmg file itself stays un-ticketed).
#
# Credentials (pick ONE; nothing secret is stored in this script):
#   A. Keychain profile (recommended). One-time:
#        xcrun notarytool store-credentials accented-notary \
#          --apple-id you@example.com --team-id D6X5HPDXAG --password <app-specific-password>
#      then:  NOTARY_KEYCHAIN_PROFILE=accented-notary ./Scripts/notarize.sh
#   B. Inline:  NOTARY_APPLE_ID=you@example.com NOTARY_PASSWORD=<app-specific-pw> ./Scripts/notarize.sh
#      (NOTARY_TEAM_ID defaults to the Developer ID team below.)
#   App-specific password: https://account.apple.com → Sign-In and Security → App-Specific Passwords.
#
# Env knobs:
#   OUTPUT_DIR           where the DMG lands (default: ~/Downloads)
#   SKIP_DMG_NOTARIZE=1  notarize/staple the app only, skip the DMG pass
#   NOTARY_TEAM_ID       override the team id (default: the Developer ID team)

set -euo pipefail

# --- Configuration ---------------------------------------------------------------------------
readonly APP_NAME="Accented"
readonly DEFAULT_TEAM_ID="D6X5HPDXAG"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly APP_BUNDLE="${REPO_ROOT}/dist/${APP_NAME}.app"
readonly OUT_DIR="${OUTPUT_DIR:-${HOME}/Downloads}"
readonly DMG_PATH="${OUT_DIR}/${APP_NAME}.dmg"

# Styled-install-window asset. A HiDPI multi-representation TIFF (640x400 @1x + 1280x800 @2x,
# built from background.svg via `tiffutil -cathidpicheck`). It MUST be HiDPI-tagged: Finder draws a
# DMG background at its natural POINT size, so a bare 1280px PNG would render at 1280pt (2x oversized,
# misaligned with the point-space icon positions). The TIFF draws at 640x400 pt — crisp on Retina and
# in the same coordinate space as the icon positions below. The committed asset is what the styling
# step copies in, so the build needs no SVG rasterizer.
readonly DMG_BACKGROUND="${REPO_ROOT}/Sources/${APP_NAME}/Resources/dmg/background.tiff"
# Install-window layout (logical points; background is this size at 2x). The Finder window is
# sized to the background and the two icons are placed to line up with its drop-target frames + arrow.
readonly DMG_WIN_W=640 DMG_WIN_H=400
readonly DMG_APP_X=160 DMG_APP_Y=205     # Accented.app icon centre (left frame)
readonly DMG_APPS_X=480 DMG_APPS_Y=205   # /Applications symlink icon centre (right frame)
readonly DMG_ICON_SIZE=100

# --- Preflight: tools ------------------------------------------------------------------------
command -v xcrun   >/dev/null || { echo "ERROR: xcrun not found (install Command Line Tools)." >&2; exit 1; }
xcrun --find notarytool >/dev/null 2>&1 || { echo "ERROR: notarytool not available (needs Xcode 13+ CLT)." >&2; exit 1; }
command -v hdiutil >/dev/null || { echo "ERROR: hdiutil not found." >&2; exit 1; }

# --- Preflight: notarization credentials -----------------------------------------------------
# Build the auth argument array once; reused for every notarytool call.
NOTARY_AUTH=()
if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    NOTARY_AUTH=(--keychain-profile "${NOTARY_KEYCHAIN_PROFILE}")
    echo "==> Notarizing with keychain profile '${NOTARY_KEYCHAIN_PROFILE}'"
elif [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
    NOTARY_AUTH=(--apple-id "${NOTARY_APPLE_ID}" --team-id "${NOTARY_TEAM_ID:-${DEFAULT_TEAM_ID}}" --password "${NOTARY_PASSWORD}")
    echo "==> Notarizing as ${NOTARY_APPLE_ID} (team ${NOTARY_TEAM_ID:-${DEFAULT_TEAM_ID}})"
else
    cat >&2 <<EOF
ERROR: no notarization credentials.

Set up a keychain profile once (recommended):
  xcrun notarytool store-credentials accented-notary \\
    --apple-id you@example.com --team-id ${DEFAULT_TEAM_ID} --password <app-specific-password>
then run:
  NOTARY_KEYCHAIN_PROFILE=accented-notary ./Scripts/notarize.sh

…or pass inline:
  NOTARY_APPLE_ID=you@example.com NOTARY_PASSWORD=<app-specific-pw> ./Scripts/notarize.sh
EOF
    exit 1
fi

# Temp workspace, cleaned on any exit.
WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "${WORK_DIR}"; }
trap cleanup EXIT

# --- 1. Build + sign (delegates to package.sh) -----------------------------------------------
echo "==> Building + signing ${APP_NAME}…"
"${SCRIPT_DIR}/package.sh"
[[ -d "${APP_BUNDLE}" ]] || { echo "ERROR: ${APP_BUNDLE} missing after package.sh" >&2; exit 1; }

# --- 2. Notarize the app ---------------------------------------------------------------------
# notarytool needs a container (zip/dmg/pkg), not a bare .app. ditto --keepParent zips the bundle.
echo "==> Zipping app for notarization…"
APP_ZIP="${WORK_DIR}/${APP_NAME}.zip"
ditto -c -k --keepParent "${APP_BUNDLE}" "${APP_ZIP}"

echo "==> Submitting app to Apple notary service (this waits for the result)…"
xcrun notarytool submit "${APP_ZIP}" "${NOTARY_AUTH[@]}" --wait

# --- 3. Staple the app -----------------------------------------------------------------------
echo "==> Stapling the app…"
xcrun stapler staple "${APP_BUNDLE}"
xcrun stapler validate "${APP_BUNDLE}"

# --- 4. Build the DMG from the stapled app ---------------------------------------------------
# A styled install window: a brand background with a "drag onto Applications" arrow and the two
# icons positioned to match it. Finder can only persist that layout (window size, icon view, background
# picture, icon positions — all stored in the volume's .DS_Store) on a MOUNTED READ-WRITE image driven
# via AppleScript, so we build UDRW → style → convert to the final compressed UDZO. The AppleScript step
# needs a GUI login session + Automation (Apple Events → Finder) consent; release is cut locally, where
# that holds. Set DMG_PLAIN=1 (or omit the background asset) to fall back to a plain, unstyled DMG —
# e.g. on a headless box — still a valid, notarizable installer (app + Applications symlink).
echo "==> Building DMG at ${DMG_PATH}…"
mkdir -p "${OUT_DIR}"
rm -f "${DMG_PATH}"

if [[ "${DMG_PLAIN:-0}" == "1" || ! -f "${DMG_BACKGROUND}" ]]; then
    [[ -f "${DMG_BACKGROUND}" ]] || echo "==> NOTE: ${DMG_BACKGROUND} missing — building a PLAIN (unstyled) DMG."
    [[ "${DMG_PLAIN:-0}" == "1" ]] && echo "==> DMG_PLAIN=1 — building a PLAIN (unstyled) DMG."
    STAGE_DIR="${WORK_DIR}/dmg"
    mkdir -p "${STAGE_DIR}"
    cp -R "${APP_BUNDLE}" "${STAGE_DIR}/"
    ln -s /Applications "${STAGE_DIR}/Applications"   # drag-to-install affordance
    hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGE_DIR}" -ov -format UDZO "${DMG_PATH}" >/dev/null
else
    echo "==> Styling the install window (background + icon layout)…"
    RW_DMG="${WORK_DIR}/${APP_NAME}-rw.dmg"
    # Stage the volume contents in a folder first, then create the writable image FROM that folder:
    # `hdiutil create -format` requires a `-srcfolder`/`-srcdevice`, so a blank `-format UDRW` is rejected.
    # `-size 200m` adds slack over the staged content for the .DS_Store the styling writes.
    STAGE_DIR="${WORK_DIR}/stage"
    mkdir -p "${STAGE_DIR}/.background"
    cp -R "${APP_BUNDLE}" "${STAGE_DIR}/"
    ln -s /Applications "${STAGE_DIR}/Applications"
    cp "${DMG_BACKGROUND}" "${STAGE_DIR}/.background/background.tiff"
    # Detach any stale mount of our volume name from a prior run / Finder, so we get a clean "/Volumes/Accented".
    hdiutil detach "/Volumes/${APP_NAME}" -force >/dev/null 2>&1 || true
    hdiutil create -srcfolder "${STAGE_DIR}" -volname "${APP_NAME}" -fs "HFS+" \
        -format UDRW -size 200m -ov "${RW_DMG}" >/dev/null
    # Mount and resolve the actual mount point (could be "/Volumes/Accented 1" if the name collides).
    MOUNT_OUT="$(hdiutil attach "${RW_DMG}" -nobrowse -noautoopen -noverify)"
    MOUNT_DIR="$(echo "${MOUNT_OUT}" | awk -F'\t' '/\/Volumes\// { print $NF }' | tail -1)"
    [[ -d "${MOUNT_DIR}" ]] || { echo "ERROR: could not resolve DMG mount point." >&2; exit 1; }
    VOL_NAME="$(basename "${MOUNT_DIR}")"

    # Drive Finder to set the window + icon layout; persisted into the volume's .DS_Store. The contents
    # (app, Applications symlink, .background) are already on the volume from the staging folder above.
    osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "${VOL_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {300, 150, $((300 + DMG_WIN_W)), $((150 + DMG_WIN_H))}
        set vo to the icon view options of container window
        set arrangement of vo to not arranged
        set icon size of vo to ${DMG_ICON_SIZE}
        set text size of vo to 12
        set background picture of vo to file ".background:background.tiff"
        set position of item "${APP_NAME}.app" of container window to {${DMG_APP_X}, ${DMG_APP_Y}}
        set position of item "Applications" of container window to {${DMG_APPS_X}, ${DMG_APPS_Y}}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

    sync
    hdiutil detach "${MOUNT_DIR}" -force >/dev/null
    # Compress to the final read-only image that ships.
    hdiutil convert "${RW_DMG}" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}" >/dev/null
fi

# --- 5. Notarize + staple the DMG (unless skipped) -------------------------------------------
if [[ "${SKIP_DMG_NOTARIZE:-0}" == "1" ]]; then
    echo "==> SKIP_DMG_NOTARIZE=1 — leaving the DMG un-notarized (the app inside is stapled)."
else
    echo "==> Submitting DMG to Apple notary service…"
    xcrun notarytool submit "${DMG_PATH}" "${NOTARY_AUTH[@]}" --wait
    echo "==> Stapling the DMG…"
    xcrun stapler staple "${DMG_PATH}"
    xcrun stapler validate "${DMG_PATH}"
fi

# --- 6. Verify Gatekeeper acceptance of the app ----------------------------------------------
echo "==> Gatekeeper assessment of the app:"
spctl --assess --type execute --verbose=2 "${APP_BUNDLE}" || true

echo ""
echo "==> Done (signed + notarized, local)."
echo "App:  ${APP_BUNDLE}"
echo "DMG:  ${DMG_PATH}"
