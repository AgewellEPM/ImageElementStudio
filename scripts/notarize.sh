#!/usr/bin/env bash
# =============================================================================
# notarize.sh - Build, sign, package, and notarize Image Element Studio
# =============================================================================
#
# This script performs the full release pipeline:
#   1. Builds a release binary with Swift Package Manager
#   2. Creates a macOS .app bundle
#   3. Code signs the app with a Developer ID certificate
#   4. Creates a DMG disk image
#   5. Submits the DMG for Apple notarization
#   6. Staples the notarization ticket to the DMG
#
# Usage:
#   Via environment variables:
#     export SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#     export TEAM_ID="XXXXXXXXXX"
#     export APPLE_ID="your@email.com"           # For notarytool
#     export APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"   # App-specific password
#     ./scripts/notarize.sh
#
#   Via command-line arguments:
#     ./scripts/notarize.sh \
#       --identity "Developer ID Application: Your Name (TEAMID)" \
#       --team-id "XXXXXXXXXX" \
#       --apple-id "your@email.com" \
#       --password "xxxx-xxxx-xxxx-xxxx"
#
#   Optional flags:
#     --version "1.0.0"    Set the version string (default: 1.0.0)
#     --build "1"          Set the build number (default: 1)
#     --skip-notarize      Build and sign, but skip notarization step
#     --help               Show this help message
#
# Prerequisites:
#   - Xcode command line tools installed
#   - A valid "Developer ID Application" certificate in your keychain
#   - An app-specific password for notarytool (https://appleid.apple.com)
#   - Swift toolchain installed
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration defaults
# ---------------------------------------------------------------------------
APP_NAME="Image Element Studio"
EXECUTABLE_NAME="ImageElementStudio"
BUNDLE_ID="com.imageelementstudio.app"
MIN_MACOS_VERSION="14.0"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SKIP_NOTARIZE=false

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/release"
OUTPUT_DIR="$PROJECT_DIR/.build/release-output"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
DMG_PATH="$OUTPUT_DIR/${EXECUTABLE_NAME}-${VERSION}.dmg"

# Signing (from env vars by default)
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
TEAM_ID="${TEAM_ID:-}"
APPLE_ID="${APPLE_ID:-}"
APP_PASSWORD="${APP_PASSWORD:-}"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
info() {
    echo "===> $*"
}

error() {
    echo "ERROR: $*" >&2
    exit 1
}

usage() {
    # Print the header comment block as usage
    sed -n '/^# Usage:/,/^# ====/p' "$0" | sed 's/^# //' | sed 's/^#//' | head -n -1
    exit 0
}

# ---------------------------------------------------------------------------
# Parse command-line arguments (override env vars if provided)
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --identity)
            SIGNING_IDENTITY="$2"
            shift 2
            ;;
        --team-id)
            TEAM_ID="$2"
            shift 2
            ;;
        --apple-id)
            APPLE_ID="$2"
            shift 2
            ;;
        --password)
            APP_PASSWORD="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --build)
            BUILD_NUMBER="$2"
            shift 2
            ;;
        --skip-notarize)
            SKIP_NOTARIZE=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            error "Unknown argument: $1. Use --help for usage."
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate required parameters
# ---------------------------------------------------------------------------
if [[ -z "$SIGNING_IDENTITY" ]]; then
    error "SIGNING_IDENTITY not set. Provide via env var or --identity flag.
Example: export SIGNING_IDENTITY=\"Developer ID Application: Your Name (TEAMID)\""
fi

if [[ -z "$TEAM_ID" ]]; then
    error "TEAM_ID not set. Provide via env var or --team-id flag.
Example: export TEAM_ID=\"XXXXXXXXXX\""
fi

if [[ "$SKIP_NOTARIZE" == false ]]; then
    if [[ -z "$APPLE_ID" ]]; then
        error "APPLE_ID not set. Required for notarization. Provide via env var or --apple-id flag.
Use --skip-notarize to skip notarization."
    fi
    if [[ -z "$APP_PASSWORD" ]]; then
        error "APP_PASSWORD not set. Required for notarization. Provide via env var or --password flag.
Generate an app-specific password at https://appleid.apple.com
Use --skip-notarize to skip notarization."
    fi
fi

# ---------------------------------------------------------------------------
# Step 1: Build release binary
# ---------------------------------------------------------------------------
info "Building release binary..."
cd "$PROJECT_DIR"
swift build -c release

EXECUTABLE_PATH="$BUILD_DIR/$EXECUTABLE_NAME"
if [[ ! -f "$EXECUTABLE_PATH" ]]; then
    error "Build succeeded but executable not found at: $EXECUTABLE_PATH"
fi
info "Build complete: $EXECUTABLE_PATH"

# ---------------------------------------------------------------------------
# Step 2: Create .app bundle
# ---------------------------------------------------------------------------
info "Creating .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy the executable
cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

# Copy entitlements if they exist
ENTITLEMENTS_PATH="$PROJECT_DIR/ImageElementStudio.entitlements"
if [[ ! -f "$ENTITLEMENTS_PATH" ]]; then
    info "Warning: No entitlements file found at $ENTITLEMENTS_PATH"
fi

# Copy Info.plist and substitute placeholders
PLIST_TEMPLATE="$PROJECT_DIR/Resources/Info.plist"
if [[ -f "$PLIST_TEMPLATE" ]]; then
    sed \
        -e "s/\$(MARKETING_VERSION)/$VERSION/g" \
        -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD_NUMBER/g" \
        "$PLIST_TEMPLATE" > "$APP_BUNDLE/Contents/Info.plist"
    info "Info.plist created with version $VERSION (build $BUILD_NUMBER)"
else
    # Generate a minimal Info.plist if template doesn't exist
    info "Warning: No Info.plist template found. Generating minimal plist."
    cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS_VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST
fi

# Copy any additional resources from the Resources directory
if [[ -d "$PROJECT_DIR/Resources" ]]; then
    for f in "$PROJECT_DIR/Resources/"*; do
        basename_f="$(basename "$f")"
        # Skip Info.plist (already handled above)
        if [[ "$basename_f" != "Info.plist" ]]; then
            cp -R "$f" "$APP_BUNDLE/Contents/Resources/"
        fi
    done
fi

info ".app bundle created at: $APP_BUNDLE"

# ---------------------------------------------------------------------------
# Step 3: Code sign the app bundle
# ---------------------------------------------------------------------------
info "Code signing with identity: $SIGNING_IDENTITY"

CODESIGN_ARGS=(
    --force
    --options runtime
    --timestamp
    --sign "$SIGNING_IDENTITY"
)

# Add entitlements if the file exists
if [[ -f "$ENTITLEMENTS_PATH" ]]; then
    CODESIGN_ARGS+=(--entitlements "$ENTITLEMENTS_PATH")
    info "Using entitlements: $ENTITLEMENTS_PATH"
fi

# Sign the executable inside the bundle
codesign "${CODESIGN_ARGS[@]}" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

# Sign the entire bundle
codesign "${CODESIGN_ARGS[@]}" "$APP_BUNDLE"

# Verify the signature
info "Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
info "Code signing verified successfully."

# ---------------------------------------------------------------------------
# Step 4: Create DMG
# ---------------------------------------------------------------------------
info "Creating DMG..."
rm -f "$DMG_PATH"

# Create a temporary DMG directory with the app and an Applications symlink
DMG_STAGING="$OUTPUT_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGING"

# Sign the DMG
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"

info "DMG created at: $DMG_PATH"

# ---------------------------------------------------------------------------
# Step 5: Submit for notarization
# ---------------------------------------------------------------------------
if [[ "$SKIP_NOTARIZE" == true ]]; then
    info "Skipping notarization (--skip-notarize was set)."
    info ""
    info "Build complete! Output files:"
    info "  App bundle: $APP_BUNDLE"
    info "  DMG:        $DMG_PATH"
    exit 0
fi

info "Submitting DMG for notarization..."
info "This may take several minutes..."

xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait

# ---------------------------------------------------------------------------
# Step 6: Staple the notarization ticket
# ---------------------------------------------------------------------------
info "Stapling notarization ticket to DMG..."
xcrun stapler staple "$DMG_PATH"

# Verify stapling
info "Verifying notarization..."
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH" || true

info ""
info "=============================================="
info "  Notarization complete!"
info "=============================================="
info "  App bundle: $APP_BUNDLE"
info "  DMG:        $DMG_PATH"
info "  Version:    $VERSION (build $BUILD_NUMBER)"
info "=============================================="
info ""
info "The DMG is ready for distribution."
