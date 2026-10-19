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
#   retain the same signing identity across builds. Otherwise, tries an
#   Apple Development identity before falling back to adhoc signing ("-").
#   A stable identity helps macOS recognize rebuilt apps for permissions.
#
#   Force a specific identity by setting CODESIGN_IDENTITY=<name or hash>.
# ============================================================================

set -eo pipefail

APP_NAME="EzSwitch"
SCHEME="EzSwitch"

# Single source of truth for Marketing Version: project.pbxproj MARKETING_VERSION
# (the Info.plist only references it via $(MARKETING_VERSION); unless overridden via VERSION=...)
if [ -z "${VERSION:-}" ]; then
    VERSION=$(grep -m1 'MARKETING_VERSION' EzSwitch.xcodeproj/project.pbxproj | sed 's/.*MARKETING_VERSION = //;s/;//' || echo "")
    VERSION="${VERSION:-1.1.0}"
fi
BUNDLE_ID=$(grep -m1 'PRODUCT_BUNDLE_IDENTIFIER' EzSwitch.xcodeproj/project.pbxproj | sed 's/.*PRODUCT_BUNDLE_IDENTIFIER = //;s/;//')
BUNDLE_ID="${BUNDLE_ID:-alexrel.EzSwitch}"

# Single source of truth for the deployment target: project.pbxproj
# MACOSX_DEPLOYMENT_TARGET. The swiftc fallback below does not go through
# xcodebuild, so it must be told the same minimum or it would emit a binary
# accepting an older macOS than the Xcode build does.
MACOS_MIN=$(grep -m1 'MACOSX_DEPLOYMENT_TARGET' EzSwitch.xcodeproj/project.pbxproj | sed 's/.*MACOSX_DEPLOYMENT_TARGET = //;s/;//')
MACOS_MIN="${MACOS_MIN:-15.4}"

# Automatically compute build number & git commit hash from git
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")
GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")

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

    log "${YELLOW}🧹 Preparing build directory...${NC}"
    rm -rf "$BUILD_DIR/"
    mkdir -p "$EXPORT_DIR"
    log "${GREEN}✅ Ready${NC}\n"

    log "${YELLOW}🔍 Finding Xcode project...${NC}"
    # shellcheck disable=SC2207
    local XCODE_ARGS=($(find_xcode_container))
    log "${GREEN}✅ Found: ${XCODE_ARGS[*]}${NC}\n"

    log "${YELLOW}📦 Building Release app (signed with: $SIGN_IDENTITY)…${NC}"
    if xcodebuild build \
        "${XCODE_ARGS[@]}" \
        -scheme "$SCHEME" \
        -configuration Release \
        -derivedDataPath "$DERIVED_DATA" \
        MARKETING_VERSION="$VERSION" \
        CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
        CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
        ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS=NO \
        OTHER_CODE_SIGN_FLAGS="--options=runtime --timestamp=none" \
        -quiet 2>/dev/null && [ -f "$DERIVED_DATA/Build/Products/Release/$APP_NAME.app/Contents/MacOS/$APP_NAME" ]; then
        cp -R "$DERIVED_DATA/Build/Products/Release/$APP_NAME.app" "$EXPORT_DIR/$APP_NAME.app"
    else
        log "${YELLOW}⚡ Compiling Release binary via swiftc…${NC}"
        if [ -d "./$APP_NAME.app" ]; then
            cp -R "./$APP_NAME.app" "$EXPORT_DIR/$APP_NAME.app"
        else
            mkdir -p "$EXPORT_DIR/$APP_NAME.app/Contents/MacOS" "$EXPORT_DIR/$APP_NAME.app/Contents/Resources"
            cp "EzSwitch/Info.plist" "$EXPORT_DIR/$APP_NAME.app/Contents/Info.plist"
            # swiftc path doesn't run xcodebuild's Info.plist preprocessing,
            # so resolve the $(VAR) placeholders manually.
            /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" \
                "$EXPORT_DIR/$APP_NAME.app/Contents/Info.plist"
            /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" \
                "$EXPORT_DIR/$APP_NAME.app/Contents/Info.plist"
            /usr/libexec/PlistBuddy -c "Set :CFBundleDevelopmentRegion en" \
                "$EXPORT_DIR/$APP_NAME.app/Contents/Info.plist"
            /usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MACOS_MIN" \
                "$EXPORT_DIR/$APP_NAME.app/Contents/Info.plist"
        fi
        cp -R "EzSwitch/en.lproj" "$EXPORT_DIR/$APP_NAME.app/Contents/Resources/"
        cp -R "EzSwitch/ru.lproj" "$EXPORT_DIR/$APP_NAME.app/Contents/Resources/"
        swiftc \
            -module-cache-path "$DERIVED_DATA/ModuleCache.noindex" \
            -sdk "$(xcrun --show-sdk-path)" \
            -target "arm64-apple-macosx$MACOS_MIN" \
            -O \
            -module-name "$APP_NAME" \
            EzSwitch/*.swift EzSwitch/Mappers/*.swift \
            -o "$EXPORT_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"
    fi

    [ -d "$EXPORT_DIR/$APP_NAME.app" ] || { log "${RED}❌ Build failed${NC}"; exit 1; }
    log "${GREEN}✅ Application built: $EXPORT_DIR/$APP_NAME.app${NC}\n"

    # Inject version metadata into the app bundle Info.plist before signing
    local app_plist="$EXPORT_DIR/$APP_NAME.app/Contents/Info.plist"
    if [ -f "$app_plist" ]; then
        log "${YELLOW}🏷  Version metadata: v$VERSION (build $BUILD_NUMBER · $GIT_HASH)${NC}"
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$app_plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$app_plist" 2>/dev/null || true

        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$app_plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$app_plist" 2>/dev/null || true

        /usr/libexec/PlistBuddy -c "Set :GitCommitHash $GIT_HASH" "$app_plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :GitCommitHash string $GIT_HASH" "$app_plist" 2>/dev/null || true
    fi

    # Re-sign the exported app with our chosen identity so every build has a
    # consistent Designated Requirement (not a per-build CDHash).
    log "${YELLOW}🔏 Re-signing exported app…${NC}"
    if [ "$SIGN_IDENTITY" = "-" ]; then
        codesign --force --deep \
            --sign "$SIGN_IDENTITY" \
            --identifier "alexrel.EzSwitch" \
            --options runtime \
            --timestamp=none \
            -r='designated => identifier "alexrel.EzSwitch"' \
            "$EXPORT_DIR/$APP_NAME.app" 2>&1 | sed 's/^/   /'
    else
        codesign --force --deep \
            --sign "$SIGN_IDENTITY" \
            --options runtime \
            --timestamp=none \
            "$EXPORT_DIR/$APP_NAME.app" 2>&1 | sed 's/^/   /'
    fi

    # Keep root ./EzSwitch.app in sync if present
    if [ -d "./$APP_NAME.app" ]; then
        rm -rf "./$APP_NAME.app"
        cp -R "$EXPORT_DIR/$APP_NAME.app" "./$APP_NAME.app"
    fi

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

    # Ad-hoc sign the DMG / Portable copy so distribution does not depend on
    # the local Apple Development signing identity used for development builds.
    log "${YELLOW}🌍 Signing DMG app with portable universal signature (for other Macs / GitHub)…${NC}"
    codesign --force --deep \
        --sign "-" \
        --identifier "alexrel.EzSwitch" \
        --options runtime \
        --timestamp=none \
        -r='designated => identifier "alexrel.EzSwitch"' \
        "$staging/$APP_NAME.app" 2>&1 | sed 's/^/   /'

    mkdir -p "$BUILD_DIR/Portable"
    if [ "$app_path" != "$BUILD_DIR/Portable/$APP_NAME.app" ]; then
        rm -rf "$BUILD_DIR/Portable/$APP_NAME.app"
        cp -R "$staging/$APP_NAME.app" "$BUILD_DIR/Portable/$APP_NAME.app"
    fi
    rm -f "$BUILD_DIR/${APP_NAME}-Portable.zip"
    ditto -c -k --sequesterRsrc --keepParent "$BUILD_DIR/Portable/$APP_NAME.app" "$BUILD_DIR/${APP_NAME}-Portable.zip"

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
log "${BLUE}🚀 Build $APP_NAME (mode: $MODE, v$VERSION, build $BUILD_NUMBER · $GIT_HASH)${NC}"
log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

case "$MODE" in
    all)
        build_app
        build_dmg
        ;;
    release)
        # Portable build for distribution to other Macs / GitHub Releases:
        # Uses ad-hoc signing, Hardened Runtime, and an identifier-based requirement.
        export CODESIGN_IDENTITY="-"
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
        echo "  ./build.sh            # build app + DMG"
        echo "  ./build.sh release    # portable DMG for other Macs / GitHub"
        echo "  ./build.sh app        # build app only"
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
echo "  • Local App (сохраняет разрешения при пересборке): $EXPORT_DIR/$APP_NAME.app"
if [ -d "$BUILD_DIR/Portable/$APP_NAME.app" ]; then
    echo "  • Portable App (для других Маков / GitHub):       $BUILD_DIR/Portable/$APP_NAME.app"
fi
if [ -f "$DMG_PATH" ]; then
    echo "  • Portable DMG (для других Маков / GitHub):       $DMG_PATH"
fi
echo ""
echo "🖥  Установка на другом Маке (из DMG или GitHub):"
echo "  1. Перетащите EzSwitch.app в папку /Applications"
echo "  2. При первом запуске (если macOS заблокирует запуск):"
echo "     • Системные настройки → Конфиденциальность и безопасность → нажать «Подтвердить вход» («Open Anyway»)"
echo "     • Либо в Терминале: xattr -cr /Applications/EzSwitch.app"
echo "  3. Выдайте разрешения в Системные настройки → Конфиденциальность и безопасность:"
echo "     • Мониторинг ввода (Input Monitoring)"
echo "     • Универсальный доступ (Accessibility)"
