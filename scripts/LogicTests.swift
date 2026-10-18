import Foundation

// Standalone test harness for the pure logic in EzSwitch.
//
// The app target has no XCTest bundle (the editor-only project would need a
// separate test target), so this file is compiled directly against the
// dependency-free sources:
//
//   swiftc EzSwitch/Constants.swift \
//          EzSwitch/Mappers/KeyboardLayoutUtility.swift \
//          EzSwitch/Mappers/LayoutMapperPreset.swift \
//          EzSwitch/Mappers/LayoutMapperPreset+Transform.swift \
//          EzSwitch/Mappers/Hotkey.swift \
//          EzSwitch/WordMatcher.swift \
//          scripts/LogicTests.swift -o /tmp/ezswitch-logic-tests
//
// Or simply: ./scripts/run-logic-tests.sh
//
// Run it after changing WordMatcher, LayoutMapperPreset or Hotkey.

var failures = 0

func check(_ condition: Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
    if !condition {
        failures += 1
        print("❌ \(message) (\(file):\(line))")
    }
}

func equal<T: Equatable>(_ actual: T, _ expected: T, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected {
        failures += 1
        print("❌ \(message): expected \(expected), got \(actual) (\(file):\(line))")
    }
}

// MARK: - WordMatcher

func testWordMatcher() {
    let entries = ["ghbdtn": "привет", "пше": "git", "оыщт": "json"]

    equal(WordMatcher.findMatch(word: "ghbdtn", in: entries)?.replacement, "привет", "exact match")
    equal(WordMatcher.findMatch(word: "GHBDTN", in: entries)?.replacement, "ПРИВЕТ", "all caps restored")
    equal(WordMatcher.findMatch(word: "Ghbdtn", in: entries)?.replacement, "Привет", "capitalized restored")
    equal(WordMatcher.findMatch(word: "ПШЕ", in: entries)?.replacement, "GIT", "cyrillic caps restored")
    equal(WordMatcher.findMatch(word: "ОЫЩТ", in: entries)?.replacement, "JSON", "lowercase entry matched from caps input")
    check(WordMatcher.findMatch(word: "unknown", in: entries) == nil, "unknown word returns nil")
    equal(WordMatcher.restoreCase(from: "GiT", to: "git"), "GiT", "mixed case copied per character")
    equal(WordMatcher.restoreCase(from: "ghbdtn", to: "привет"), "привет", "lowercase stays lowercase")
}

// MARK: - LayoutMapperPreset

private func makePreset() -> LayoutMapperPreset {
    LayoutMapperPreset(
        name: "test",
        fromLayout: "Russian – PC",
        toLayout: "ABC",
        mapping: [
            "й": "q", "ц": "w", "е": "t", "н": "y", "г": "u", "ш": "i",
            "ф": "a", "ы": "s", "в": "d", "п": "g", "р": "h", "и": "b", "т": "n"
        ]
    )
}

func testPresetTransform() {
    let preset = makePreset()

    equal(preset.transform("привет"), "ghbdtn", "forward: ru → en")
    equal(preset.transform("ghbdtn"), "привет", "reverse: en → ru")
    equal(preset.transform(""), "", "empty input")
    equal(preset.transform("123 !?"), "123 !?", "unmapped characters pass through")

    // Direction is decided by which side has more exclusive hits; ties go forward.
    equal(preset.transform("ghbdtn привет"), "ghbdtn ghbdtn", "mixed input with equal hits goes forward")

    // Reversed mapping must skip multi-character targets.
    var multi = preset
    multi.mapping["я"] = "QQ"
    equal(multi.reversedCharacterMapping()["Q"], nil, "multi-char target is not reversible")
    equal(multi.transform("привет"), "ghbdtn", "multi-char target does not break forward mapping")

    // Extra mappings are applied after the character map.
    var withExtra = preset
    withExtra.extraMappings = [
        LayoutMapperPreset.ExtraMapping(source: "ghbdtn", target: "HELLO")
    ]
    equal(withExtra.transform("привет"), "HELLO", "extra mapping applied after transform")

    // mapping(from:) returns the right side for the requested direction.
    equal(preset.mapping(from: "Russian – PC")["й"], "q", "forward mapping side")
    equal(preset.mapping(from: "ABC")["q"], "й", "reversed mapping side")
    equal(preset.mapping(from: "ABC")["Q"], nil, "reversed map only inverts single-char targets")
}

// MARK: - Hotkey

func testHotkeyCoding() {
    let hotkey = Hotkey(keyCode: 46, modifiers: Constants.ModifierMask.command | Constants.ModifierMask.shift)
    guard let data = try? JSONEncoder().encode(hotkey),
          let decoded = try? JSONDecoder().decode(Hotkey.self, from: data) else {
        failures += 1
        print("❌ Hotkey round-trip failed")
        return
    }
    equal(decoded, hotkey, "hotkey round-trips through JSON")
    equal(hotkey.displayTokens, ["⌘", "⇧", "M"], "hotkey display tokens")
    equal(Hotkey.none.displayTokens, [], "unassigned hotkey has no tokens")
    check(Hotkey.none.isSet == false, "unassigned hotkey is not set")
}

// MARK: - Run

testWordMatcher()
testPresetTransform()
testHotkeyCoding()

if failures == 0 {
    print("✅ All logic tests passed")
    exit(0)
} else {
    print("❌ \(failures) failure(s)")
    exit(1)
}
