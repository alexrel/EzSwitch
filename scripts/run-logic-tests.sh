#!/bin/zsh
# Compile and run the dependency-free logic tests.
set -euo pipefail
cd "$(dirname "$0")/.."

# Top-level code is only allowed in a file named main.swift, so copy the
# harness there before compiling.
TESTS_DIR="/tmp/ezswitch-tests"
mkdir -p "$TESTS_DIR"
cp scripts/LogicTests.swift "$TESTS_DIR/main.swift"

# Exercise live lookups against the shipped catalogs rather than mocked strings.
TEST_RESOURCES="$TESTS_DIR/LocalizationTests.bundle/Contents/Resources"
mkdir -p "$TEST_RESOURCES"
cat > "$TESTS_DIR/LocalizationTests.bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>EzSwitch.LocalizationTests</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
</dict></plist>
PLIST
cp -R EzSwitch/*.lproj "$TEST_RESOURCES/"

swiftc -O \
    -module-cache-path "$TESTS_DIR/module-cache" \
    EzSwitch/AppLanguage.swift \
    EzSwitch/AppConfigs.swift \
    EzSwitch/AccessibilityTextSelection.swift \
    EzSwitch/AppLocalization.swift \
    EzSwitch/PopoverBackgroundView.swift \
    EzSwitch/Constants.swift \
    EzSwitch/LayoutRegistry.swift \
    EzSwitch/TransformSourceDetection.swift \
    EzSwitch/TransformSnapshot.swift \
    EzSwitch/TypedWordBuffer.swift \
    EzSwitch/Log.swift \
    EzSwitch/Mappers/KeyboardLayoutUtility.swift \
    EzSwitch/Mappers/LayoutMapperPreset.swift \
    EzSwitch/Mappers/LayoutMapperPreset+Transform.swift \
    EzSwitch/Mappers/MapperStore.swift \
    EzSwitch/Mappers/Hotkey.swift \
    EzSwitch/WordMatcher.swift \
    "$TESTS_DIR/main.swift" \
    -o "$TESTS_DIR/logic-tests"

exec "$TESTS_DIR/logic-tests"
