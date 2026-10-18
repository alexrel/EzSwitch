#!/bin/zsh
# Compile and run the dependency-free logic tests.
set -euo pipefail
cd "$(dirname "$0")/.."

swiftc -O \
    EzSwitch/Constants.swift \
    EzSwitch/Mappers/KeyboardLayoutUtility.swift \
    EzSwitch/Mappers/LayoutMapperPreset.swift \
    EzSwitch/Mappers/LayoutMapperPreset+Transform.swift \
    EzSwitch/Mappers/Hotkey.swift \
    EzSwitch/WordMatcher.swift \
    scripts/LogicTests.swift \
    -o /tmp/ezswitch-tests/logic-tests

exec /tmp/ezswitch-tests/logic-tests
