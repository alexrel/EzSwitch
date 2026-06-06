#!/bin/bash
# ============================================================================
# build.sh
# ----------------------------------------------------------------------------
# Build EzSwitch.app and (optionally) a DMG installer.
#
# Modes:
#   ./build.sh         — build app + DMG (default)
#   ./build.sh app     — build app only
#   ./build.sh dmg     — build DMG only from existing app
#
# Signing:
#   If a "EzSwitch Dev" codesigning identity exists in the login Keychain
#   (installed via ./scripts/setup_dev_signing.sh), it will be used to
#   produce a stable signature across builds. Otherwise, falls back to
#   adhoc signing ("-"), which is unique per build and forces you to
#   re-grant Accessibility / Input Monitoring permissions on every build.
#
#   Force a specific identity by setting CODESIGN_IDENTITY=<name or hash>.
# ============================================================================

# Note: do NOT use `set -u` — `local` variables fall out of scope after
# subshell calls (xcodebuild, codesign), which would trigger spurious
# "unbound variable" errors.
set -eo pipefail

APP_NAME="EzSwitch"
SCHEME="EzSwitch"
VERSION="1.0"

BUILD_DIR="build"
DERIVED_DATA="DerivedData"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/Release"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
DMG_PATH="$BUILD_DIR/${APP_NAME}-Installer-v${VERSION}.dmg"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

MODE="${1:-all}" # all | app | dmg
APP_PATH_ARG="${2:-}" # optional override: path to .app for dmg mode

# Logging: to stderr so we don't pollute command substitution on stdout.
# Use printf so backslashes in variables (e.g. signing identity names) are
# never interpreted as escape sequences.
log() { printf '%b\n' "$1" >&2; }

# ---------------------------------------------------------------------------
# Pick best available codesigning identity (writes to stdout only)
# ---------------------------------------------------------------------------
PREFERRED_IDENTITY="EzSwitch Dev"
FALLBACK_IDENTITY="-" # adhoc

resolve_signing_identity() {
    if [ -n "${CODESIGN_IDENTITY:-}" ]; then
        echo "$CODESIGN_IDENTITY"
        return
    fi

    # 1. Try "EzSwitch Dev" (custom self-signed identity)
    local found
    found=$(security find-identity -v -p codesigning 2>/dev/null \
            | grep -F "\"$PREFERRED_IDENTITY\"" | head -1 | awk '{print $2}' || true)

    if [ -n "$found" ]; then
        log "${GREEN}🔐 Using stable signing identity: \"$PREFERRED_IDENTITY\" ($found)${NC}" >&2
        echo "$PREFERRED_IDENTITY"
        return
    fi

    # 2. Try "Apple Development" (Personal Team or paid developer account).
    #    Real names look like: "Apple Development: user@email.com (TEAMID)".
    #    We need to use the full name as the identity so that codesign matches it.
    local apple_line
    apple_line=$(security find-identity -v -p codesigning 2>/dev/null \
                 | grep -E '"Apple Development' | head -1 || true)

    if [ -n "$apple_line" ]; then
        # Extract the full quoted name (e.g. "Apple Development: a@b.com (TEAM)")
        local apple_name
        apple_name=$(echo "$apple_line" | sed -E 's/.*"([^"]+)".*/\1/')
        local apple_hash
        apple_hash=$(echo "$apple_line" | awk '{print $2}')
        log "${GREEN}🔐 Using Apple Development identity: $apple_name ($apple_hash)${NC}" >&2
        echo "$apple_name"
        return
    fi

    # 3. Fall back to adhoc signing (will be unique per build)
    log "${YELLOW}⚠️  No stable signing identity found in Keychain — using adhoc signing${NC}" >&2
    log "${YELLOW}   For stable signatures run: ./scripts/setup_dev_signing.sh${NC}" >&2
    echo "$FALLBACK_IDENTITY"
}

find_xcode_container() {
    local xcode_args=()
    if [ -f "$APP_NAME.xcworkspace/contents.xcworkspacedata" ]; then
        xcode_args+=( -workspace "$APP_NAME.xcworkspace" )
    elif [ -f "$APP_NAME.xcodeproj/project.pbxproj" ]; then
        xcode_args+=( -project "$APP_NAME.xcodeproj" )
    else
        log "${RED}❌ .xcodeproj or .xcworkspace not found${NC}"
        exit 1
    fi
    echo "${xcode_args[@]}"
}

build_app() {
    # Default to adhoc in case the resolve function has issues
    SIGN_IDENTITY="-"
    SIGN_IDENTITY="$(resolve_signing_identity)"

    log "${YELLOW}🧹 Cleaning...${NC}"
    rm -rf "$BUILD_DIR/" "$DERIVED_DATA/"
    mkdir -p "$BUILD_DIR"
    log "${GREEN}✅ Cleaned${NC}\n"

    log "${YELLOW}🔍 Finding Xcode project...${NC}"
    # shellcheck disable=SC2207
    local XCODE_ARGS=($(find_xcode_container))
    log "${GREEN}✅ Found: ${XCODE_ARGS[*]}${NC}\n"

    log "${YELLOW}📦 Creating Archive (signed with: $SIGN_IDENTITY)…${NC}"
    xcodebuild archive \
        "${XCODE_ARGS[@]}" \
        -scheme "$SCHEME" \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        -derivedDataPath "$DERIVED_DATA" \
        CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
        OTHER_CODE_SIGN_FLAGS="--options=runtime --timestamp=none" \
        -quiet

    [ -d "$ARCHIVE_PATH" ] || { log "${RED}❌ Archive not created${NC}"; exit 1; }
    log "${GREEN}✅ Archive created${NC}\n"

    log "${YELLOW}📤 Exporting application...${NC}"
    cat > "$EXPORT_OPTIONS" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>mac-application</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>$SIGN_IDENTITY</string>
</dict>
</plist>
EOF

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$EXPORT_OPTIONS" \
        CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
        -quiet

    [ -d "$EXPORT_DIR/$APP_NAME.app" ] || { log "${RED}❌ Export failed${NC}"; exit 1; }
    log "${GREEN}✅ Application exported: $EXPORT_DIR/$APP_NAME.app${NC}\n"

    # Re-sign the exported app with our chosen identity to guarantee consistency
    log "${YELLOW}🔏 Re-signing exported app…${NC}"
    codesign --force --deep \
        --sign "$SIGN_IDENTITY" \
        --entitlements EzSwitch/EzSwitch.entitlements \
        --options runtime \
        --timestamp=none \
        "$EXPORT_DIR/$APP_NAME.app" 2>&1 | sed 's/^/   /'

    log "${GREEN}✅ Stable signature applied${NC}\n"
}

detach_dmg_if_attached() {
    local dmg="$1"
    [ -f "$dmg" ] || return 0

    local dev=""
    dev="$(hdiutil info | awk -v p="$dmg" '$0 ~ p {found=1} found && $1 ~ /^\/dev\/disk/ {print $1; exit}')"
    if [ -n "${dev:-}" ]; then
        log "${YELLOW}📎 DMG mounted ($dev) — detaching...${NC}"
        hdiutil detach -force "$dev" || true
        log "${GREEN}✅ Detached${NC}\n"
    fi
}

build_dmg() {
    local app_path="${1:-$EXPORT_DIR/$APP_NAME.app}"
    [ -d "$app_path" ] || { log "${RED}❌ .app not found: $app_path${NC}"; exit 1; }

    detach_dmg_if_attached "$DMG_PATH"

    log "${YELLOW}💿 Creating DMG...${NC}"
    mkdir -p "$BUILD_DIR"

    local temp_dir staging dmg_temp mount_dir
    temp_dir="$(mktemp -d)"
    staging="$temp_dir/dmg"
    mkdir -p "$staging"

    cp -R "$app_path" "$staging/"
    ln -s /Applications "$staging/Applications"

    dmg_temp="$temp_dir/EzSwitch-temp.dmg"
    rm -f "$DMG_PATH"

    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$staging" \
        -ov -format UDRW \
        "$dmg_temp" >/dev/null

    mount_dir="/Volumes/${APP_NAME}-dmg-$$"
    hdiutil attach "$dmg_temp" -mountpoint "$mount_dir" -nobrowse >/dev/null

    # Wait for volume to actually appear (and Finder to see it)
    for i in {1..20}; do
        if [ -d "$mount_dir" ] && ls "$mount_dir" >/dev/null 2>&1; then
            break
        fi
        sleep 0.5
    done

    # Finder styling (with retries for stable GUI application)
    STYLED=false
    for i in 1 2 3 4 5; do
        if osascript << EOF >/dev/null 2>&1
tell application "Finder"
  delay 1
  tell disk "$APP_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {400, 100, 900, 450}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 72
    set position of item "$APP_NAME.app" of container window to {150, 140}
    set position of item "Applications" of container window to {350, 140}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
EOF
        then
            STYLED=true
            break
        fi
        sleep 1
    done

    if [ "$STYLED" = false ]; then
        echo "⚠️ Finder styling failed after retries (no GUI or disk not visible). DMG will be default view."
    fi

    osascript -e "tell application \"Finder\" to close (every window whose name is \"$APP_NAME\")" >/dev/null 2>&1 || true
    sync

    # Detach with retries
    for i in 1 2 3; do
        if hdiutil detach "$mount_dir" >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    # Just in case
    if mount | grep -q "$mount_dir"; then
        diskutil unmount force "$mount_dir" >/dev/null 2>&1 || true
        sleep 1
    fi

    hdiutil convert "$dmg_temp" \
        -format UDZO \
        -imagekey zlib-level=9 \
        -o "$DMG_PATH" >/dev/null

    rm -rf "$temp_dir"

    log "${GREEN}✅ DMG created: $DMG_PATH${NC}\n"
}

log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
log "${BLUE}🚀 Build $APP_NAME (mode: $MODE)${NC}"
log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

case "$MODE" in
    all)
        build_app
        build_dmg
        ;;
    app)
        build_app
        ;;
    dmg)
        if [ -n "$APP_PATH_ARG" ]; then
            build_dmg "$APP_PATH_ARG"
        else
            build_dmg
        fi
        ;;
    *)
        echo "Usage:"
        echo "  ./build.sh            # all"
        echo "  ./build.sh all"
        echo "  ./build.sh app"
        echo "  ./build.sh dmg [path/to/EzSwitch.app]"
        echo ""
        echo "Optional environment variables:"
        echo "  CODESIGN_IDENTITY=<name or hash>  Force a specific codesigning identity"
        exit 1
        ;;
esac

log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
log "${GREEN}✅ Done${NC}"
log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo "📁 Artifacts:"
echo "  • App: $EXPORT_DIR/$APP_NAME.app"
if [ -f "$DMG_PATH" ]; then
    echo "  • DMG: $DMG_PATH"
fi
echo ""
echo "💡 Tip: To use a stable signing identity across builds, run once:"
echo "     ./scripts/setup_dev_signing.sh"
