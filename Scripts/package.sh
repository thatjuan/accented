#!/usr/bin/env bash
#
# package.sh — build Accented in release configuration, assemble a hand-made .app bundle, and sign it
# with the Developer ID identity so TCC permission grants persist across rebuilds (diarc ARCHITECTURE §7).
#
# No Xcode in this environment (CommandLineTools only) → no xcodebuild. We use SwiftPM and lay out
# the bundle by hand. Idempotent: cleans dist/ first. Prints the final .app path on success.
#
# Notes on signing:
#   - Hardened runtime is enabled (--options runtime). AX control and CGEvent posting need NO
#     entitlement (AX is TCC-gated, not entitlement-gated). So we deliberately pass no
#     --entitlements file.
#   - Non-sandboxed: no App Sandbox entitlement (sandbox forbids cross-app AX + CGEvent). This is
#     why Accented ships as a notarized Developer ID app, not via the Mac App Store.
#   - Sparkle is copied from the SwiftPM binary artifact and signed inside-out (no --deep).

set -euo pipefail

# --- Configuration ---------------------------------------------------------------------------
readonly APP_NAME="Accented"
readonly BUNDLE_ID="com.thatjuan.accented"
readonly SIGN_IDENTITY="Developer ID Application: Juan Jaramillo (D6X5HPDXAG)"

# Resolve repo root from this script's location so the script works from any CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

readonly DIST_DIR="${REPO_ROOT}/dist"
readonly APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
readonly CONTENTS_DIR="${APP_BUNDLE}/Contents"
readonly MACOS_DIR="${CONTENTS_DIR}/MacOS"
readonly RESOURCES_DIR="${CONTENTS_DIR}/Resources"
readonly INFO_PLIST_SRC="${REPO_ROOT}/Sources/${APP_NAME}/Info.plist"
# App icon. Lives in the source tree, copied into Contents/Resources as AppIcon.icns; Info.plist's
# CFBundleIconFile=AppIcon points the Dock/Finder at it. SwiftPM doesn't embed it (excluded from the
# build graph) — the bundle is hand-assembled, so it is copied here directly.
readonly ICON_SRC="${REPO_ROOT}/Sources/${APP_NAME}/Resources/AppIcon.icns"
readonly FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
readonly SPARKLE_ARTIFACT_DIR="${REPO_ROOT}/.build/artifacts/sparkle/Sparkle"

# --- Build -----------------------------------------------------------------------------------
echo "==> Building ${APP_NAME} (release)…"
cd "${REPO_ROOT}"
swift build -c release

# Resolve the actual binary path from SwiftPM rather than hardcoding .build/release.
BIN_PATH="$(swift build -c release --show-bin-path)"
readonly BUILT_BINARY="${BIN_PATH}/${APP_NAME}"

if [[ ! -x "${BUILT_BINARY}" ]]; then
    echo "ERROR: built binary not found at ${BUILT_BINARY}" >&2
    exit 1
fi

if [[ ! -f "${INFO_PLIST_SRC}" ]]; then
    echo "ERROR: Info.plist not found at ${INFO_PLIST_SRC}" >&2
    exit 1
fi

if [[ ! -f "${ICON_SRC}" ]]; then
    echo "ERROR: app icon not found at ${ICON_SRC}" >&2
    exit 1
fi

SPARKLE_FRAMEWORK_SRC=""
for slice in "${SPARKLE_ARTIFACT_DIR}"/Sparkle.xcframework/macos-*/Sparkle.framework; do
    if [[ -d "${slice}" ]]; then
        SPARKLE_FRAMEWORK_SRC="${slice}"
        break
    fi
done
readonly SPARKLE_FRAMEWORK_SRC

if [[ -z "${SPARKLE_FRAMEWORK_SRC}" || ! -d "${SPARKLE_FRAMEWORK_SRC}" ]]; then
    echo "ERROR: Sparkle.framework not found under ${SPARKLE_ARTIFACT_DIR}/Sparkle.xcframework/macos-*/" >&2
    echo "       Run 'swift package resolve' (or 'swift build') to fetch the Sparkle binary artifact." >&2
    exit 1
fi

# --- Assemble bundle (idempotent) ------------------------------------------------------------
echo "==> Assembling bundle at ${APP_BUNDLE}…"
rm -rf "${DIST_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${FRAMEWORKS_DIR}"

cp "${BUILT_BINARY}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"
cp "${INFO_PLIST_SRC}" "${CONTENTS_DIR}/Info.plist"
cp "${ICON_SRC}" "${RESOURCES_DIR}/AppIcon.icns"

# PkgInfo is a small conventional file (type + creator). Harmless to include; some tooling expects
# it for an APPL bundle.
printf 'APPL????' > "${CONTENTS_DIR}/PkgInfo"

echo "==> Embedding Sparkle.framework…"
ditto "${SPARKLE_FRAMEWORK_SRC}" "${FRAMEWORKS_DIR}/Sparkle.framework"

# --- Sign INSIDE-OUT (hardened runtime, no --deep) -------------------------------------------
# Innermost nested XPC services + helpers first, then the framework, then the app last.
# Nested Sparkle binaries KEEP their org.sparkle-project.* identifiers.
readonly SPARKLE_FW="${FRAMEWORKS_DIR}/Sparkle.framework"
readonly SPARKLE_VB="${SPARKLE_FW}/Versions/B"

echo "==> Signing Sparkle nested components (inside-out)…"
codesign --force --options runtime --sign "${SIGN_IDENTITY}" \
    "${SPARKLE_VB}/XPCServices/Installer.xpc"
codesign --force --options runtime --preserve-metadata=entitlements --sign "${SIGN_IDENTITY}" \
    "${SPARKLE_VB}/XPCServices/Downloader.xpc"
codesign --force --options runtime --sign "${SIGN_IDENTITY}" \
    "${SPARKLE_VB}/Autoupdate"
codesign --force --options runtime --sign "${SIGN_IDENTITY}" \
    "${SPARKLE_VB}/Updater.app"
codesign --force --options runtime --sign "${SIGN_IDENTITY}" \
    "${SPARKLE_FW}"

# --- Sign the app (last, after all bundle contents — incl. the framework — are in place) -----
echo "==> Signing with: ${SIGN_IDENTITY}"
codesign --force --options runtime \
    --identifier "${BUNDLE_ID}" \
    --sign "${SIGN_IDENTITY}" \
    "${APP_BUNDLE}"

# --deep on *verify* recursively validates nested signed code (wanted, and what the AC asks
# for); --deep on *sign* (above) is the forbidden thing. Different operations — not a conflict.
echo "==> Verifying signatures (deep, strict)…"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
codesign -dv --verbose=2 "${APP_BUNDLE}" || true
# spctl may report 'rejected (source=no usable signature)' until the app is notarized + stapled —
# that is expected here (notarization is a maintainer gate) and resolves after release.sh.
echo "==> Gatekeeper assessment (pre-notarization; a not-yet-notarized rejection is expected)…"
spctl --assess --type execute --verbose=2 "${APP_BUNDLE}" || true

echo ""
echo "==> Done. App bundle:"
echo "${APP_BUNDLE}"
