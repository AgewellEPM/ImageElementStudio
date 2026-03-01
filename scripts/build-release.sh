#!/usr/bin/env bash
# =============================================================================
# build-release.sh - Build a release binary of Image Element Studio
# =============================================================================
#
# A simple script that builds an optimized release binary without code signing
# or notarization. Useful for local testing of release builds.
#
# Usage:
#   ./scripts/build-release.sh
#   ./scripts/build-release.sh --app-bundle    # Also create .app bundle
#   ./scripts/build-release.sh --version 1.2.3 # Set version string
#
# The release binary will be at:
#   .build/release/ImageElementStudio
#
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
APP_NAME="Image Element Studio"
EXECUTABLE_NAME="ImageElementStudio"
BUNDLE_ID="com.imageelementstudio.app"
MIN_MACOS_VERSION="14.0"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CREATE_APP_BUNDLE=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/release"
OUTPUT_DIR="$PROJECT_DIR/.build/release-output"

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

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-bundle)
            CREATE_APP_BUNDLE=true
            shift
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --build)
            BUILD_NUMBER="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--app-bundle] [--version VERSION] [--build BUILD_NUMBER]"
            echo ""
            echo "Options:"
            echo "  --app-bundle    Create a .app bundle (unsigned) in .build/release-output/"
            echo "  --version VER   Set version string (default: 1.0.0)"
            echo "  --build NUM     Set build number (default: 1)"
            echo "  --help          Show this help message"
            exit 0
            ;;
        *)
            error "Unknown argument: $1. Use --help for usage."
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
info "Building release binary..."
cd "$PROJECT_DIR"
swift build -c release

EXECUTABLE_PATH="$BUILD_DIR/$EXECUTABLE_NAME"
if [[ ! -f "$EXECUTABLE_PATH" ]]; then
    error "Build succeeded but executable not found at: $EXECUTABLE_PATH"
fi

info "Release binary built successfully!"
info "  Executable: $EXECUTABLE_PATH"

# Show binary size
BINARY_SIZE=$(du -h "$EXECUTABLE_PATH" | cut -f1)
info "  Size: $BINARY_SIZE"

# Show architecture
ARCH_INFO=$(file "$EXECUTABLE_PATH" | sed "s|$EXECUTABLE_PATH: ||")
info "  Architecture: $ARCH_INFO"

# ---------------------------------------------------------------------------
# Optionally create .app bundle (unsigned)
# ---------------------------------------------------------------------------
if [[ "$CREATE_APP_BUNDLE" == true ]]; then
    info "Creating unsigned .app bundle..."

    APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
    rm -rf "$APP_BUNDLE"
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"

    # Copy executable
    cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

    # Generate Info.plist from template or create minimal one
    PLIST_TEMPLATE="$PROJECT_DIR/Resources/Info.plist"
    if [[ -f "$PLIST_TEMPLATE" ]]; then
        sed \
            -e "s/\$(MARKETING_VERSION)/$VERSION/g" \
            -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD_NUMBER/g" \
            "$PLIST_TEMPLATE" > "$APP_BUNDLE/Contents/Info.plist"
    else
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

    # Copy additional resources (excluding Info.plist)
    if [[ -d "$PROJECT_DIR/Resources" ]]; then
        for f in "$PROJECT_DIR/Resources/"*; do
            basename_f="$(basename "$f")"
            if [[ "$basename_f" != "Info.plist" ]]; then
                cp -R "$f" "$APP_BUNDLE/Contents/Resources/"
            fi
        done
    fi

    info "Unsigned .app bundle created at: $APP_BUNDLE"
    info ""
    info "Note: This bundle is NOT code signed. It can be run locally but"
    info "cannot be distributed. Use notarize.sh for a distributable build."
fi

info ""
info "Done! To run the release binary directly:"
info "  $EXECUTABLE_PATH"
