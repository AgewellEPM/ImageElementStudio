#!/usr/bin/env bash
set -euo pipefail

# Image Element Studio — Archive, Export & Notarize
# Usage: ./scripts/archive.sh [--skip-notarize]

SCHEME="ImageElementStudio"
PROJECT="ImageElementStudio.xcodeproj"
ARCHIVE_PATH="build/${SCHEME}.xcarchive"
EXPORT_PATH="build/export"
EXPORT_OPTIONS_PLIST="scripts/ExportOptions.plist"

SKIP_NOTARIZE=false
if [[ "${1:-}" == "--skip-notarize" ]]; then
    SKIP_NOTARIZE=true
fi

echo "==> Cleaning previous build artifacts..."
rm -rf build/

echo "==> Archiving ${SCHEME}..."
xcodebuild archive \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_PATH}" \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS="APP_STORE" \
    CODE_SIGN_STYLE=Automatic \
    | xcbeautify 2>/dev/null || true

if [[ ! -d "${ARCHIVE_PATH}" ]]; then
    echo "ERROR: Archive failed. No .xcarchive produced."
    exit 1
fi

echo "==> Exporting .app from archive..."
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}" \
    | xcbeautify 2>/dev/null || true

APP_PATH="${EXPORT_PATH}/${SCHEME}.app"
if [[ ! -d "${APP_PATH}" ]]; then
    echo "ERROR: Export failed. No .app produced."
    exit 1
fi

echo "==> Archive + export succeeded: ${APP_PATH}"

if [[ "${SKIP_NOTARIZE}" == true ]]; then
    echo "==> Skipping notarization (--skip-notarize flag set)"
    exit 0
fi

echo "==> Submitting for notarization..."
echo "    (Requires APPLE_ID, TEAM_ID, and APP_PASSWORD environment variables)"

if [[ -z "${APPLE_ID:-}" || -z "${TEAM_ID:-}" || -z "${APP_PASSWORD:-}" ]]; then
    echo "WARNING: Notarization credentials not set. Skipping notarization."
    echo "  Set APPLE_ID, TEAM_ID, and APP_PASSWORD to enable."
    exit 0
fi

# Create a zip for notarization
ZIP_PATH="build/${SCHEME}.zip"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"

xcrun notarytool submit "${ZIP_PATH}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${TEAM_ID}" \
    --password "${APP_PASSWORD}" \
    --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "${APP_PATH}"

echo "==> Done! App is signed, notarized, and stapled: ${APP_PATH}"
