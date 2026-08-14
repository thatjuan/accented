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
#   - Sparkle embedding/signing lands in #9. The binary already has an rpath of
#     @executable_path/../Frameworks (Package.swift linkerSettings) so that issue only adds the
#     framework copy + inside-out nested codesign.

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

# --- Assemble bundle (idempotent) ------------------------------------------------------------
echo "==> Assembling bundle at ${APP_BUNDLE}…"
rm -rf "${DIST_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BUILT_BINARY}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"
cp "${INFO_PLIST_SRC}" "${CONTENTS_DIR}/Info.plist"
cp "${ICON_SRC}" "${RESOURCES_DIR}/AppIcon.icns"

# PkgInfo is a small conventional file (type + creator). Harmless to include; some tooling expects
# it for an APPL bundle.
printf 'APPL????' > "${CONTENTS_DIR}/PkgInfo"

# --- Sign the app (last, after all bundle contents are in place) -----------------------------
# --deep is deliberately NOT used on sign (it would mis-sign nested Sparkle XPCs once #9 embeds
# them). Verify below uses --deep, which is a different operation.
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
