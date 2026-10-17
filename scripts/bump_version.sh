#!/bin/bash
# ============================================================================
# bump_version.sh
# ----------------------------------------------------------------------------
# Bump or inspect the Marketing Version of EzSwitch.
#
# Usage:
#   ./scripts/bump_version.sh           # print current version & build number
#   ./scripts/bump_version.sh 1.2.0     # set marketing version to 1.2.0
# ============================================================================

set -euo pipefail

INFO_PLIST="EzSwitch/Info.plist"
PBXPROJ="EzSwitch.xcodeproj/project.pbxproj"

CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "unknown")
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")
GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")

if [ $# -eq 0 ]; then
    echo "EzSwitch version info:"
    echo "  Marketing Version (CFBundleShortVersionString): $CURRENT_VERSION"
    echo "  Build Number (git commit count):                $BUILD_NUMBER"
    echo "  Git Commit Hash:                                $GIT_HASH"
    echo ""
    echo "To bump version, run:"
    echo "  $0 <new-version>  (e.g. $0 1.2.0)"
    exit 0
fi

NEW_VERSION="$1"

# Validate format: digits.digits (and optional .digits)
if [[ ! "$NEW_VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
    echo "❌ Invalid version format: '$NEW_VERSION'. Expected format like 1.2 or 1.2.0" >&2
    exit 1
fi

echo "Bumping EzSwitch version: $CURRENT_VERSION → $NEW_VERSION"

# 1. Update Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$INFO_PLIST"
echo "  ✅ Updated $INFO_PLIST"

# 2. Update project.pbxproj
sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $NEW_VERSION;/g" "$PBXPROJ"
echo "  ✅ Updated $PBXPROJ"

# 3. Update README.md if present
if [ -f "README.md" ]; then
    sed -i '' -E "s/v$CURRENT_VERSION/v$NEW_VERSION/g" README.md 2>/dev/null || true
    echo "  ✅ Updated README.md"
fi

echo ""
echo "🎉 EzSwitch is now at version $NEW_VERSION (build $BUILD_NUMBER · $GIT_HASH)"
echo ""
echo "Next steps:"
echo "  1. Test and build: ./build.sh app"
echo "  2. Commit changes: git commit -am \"chore: bump version to $NEW_VERSION\""
echo "  3. Optional tag:   git tag -a \"v$NEW_VERSION\" -m \"Release v$NEW_VERSION\""
