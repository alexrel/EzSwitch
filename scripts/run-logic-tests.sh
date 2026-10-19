#!/bin/zsh
# Compile and run the dependency-free logic tests.
set -euo pipefail
cd "$(dirname "$0")/.."

# Top-level code is only allowed in a file named main.swift, so copy the
# harness there before compiling.
TESTS_DIR="/tmp/ezswitch-tests"
mkdir -p "$TESTS_DIR"
cp scripts/LogicTests.swift "$TESTS_DIR/main.swift"

swiftc -O \
    EzSwitch/Constants.swift \
    EzSwitch/LayoutRegistry.swift \
    EzSwitch/Mappers/KeyboardLayoutUtility.swift \
    EzSwitch/Mappers/LayoutMapperPreset.swift \
    EzSwitch/Mappers/LayoutMapperPreset+Transform.swift \
    EzSwitch/Mappers/Hotkey.swift \
    EzSwitch/WordMatcher.swift \
    "$TESTS_DIR/main.swift" \
    -o "$TESTS_DIR/logic-tests"

exec "$TESTS_DIR/logic-tests"
