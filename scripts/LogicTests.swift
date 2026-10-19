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

    // apply(_:from:) returns the right side for the requested direction.
    equal(preset.apply("й", from: "Russian – PC"), "q", "forward mapping side")
    equal(preset.apply("q", from: "ABC"), "й", "reversed mapping side")
    // The reverse direction inverts with longest-match, so multi-char targets
    // survive instead of being dropped.
    equal(multi.apply("QQ", from: "ABC"), "я", "reverse inverts multi-char targets")
    equal(preset.apply("й п", from: "Russian – PC"), "q g", "forward maps char by char")
    equal(preset.apply("q g", from: "ABC"), "й п", "reverse maps char by char")
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

// MARK: - LayoutPair normalization

func testLayoutPairNormalization() {
    // Equality tolerates dash style (`–`, `—`, `-`) and letter case.
    check(LayoutPair(from: "Russian – PC", to: "ABC")
        == LayoutPair(from: "Russian - PC", to: "ABC"), "pair equality normalizes dash style")
    check(LayoutPair(from: "Russian — PC", to: "ABC")
        == LayoutPair(from: "russian — pc", to: "abc"), "pair equality ignores letter case")
    check(LayoutPair(from: " Russian – PC ", to: "ABC")
        == LayoutPair(from: "Russian - PC", to: "ABC"), "pair equality trims whitespace")
    check(LayoutPair(from: "ABC", to: "ABC") != LayoutPair(from: "ABC", to: "Hebrew"),
          "distinct layouts are not equal")
    // Hashing must agree with equality so dictionaries keyed by pair keep working.
    let a = Set([LayoutPair(from: "Russian – PC", to: "ABC")])
    check(a.contains(LayoutPair(from: "russian - pc", to: "abc")), "hash follows normalized equality")
    // Storage keys are normalized, and migration of old raw keys matches them.
    let pair = LayoutPair(from: "Russian – PC", to: "ABC")
    check(LayoutPair.migrateKey("Russian – PC|ABC") == pair.key, "migrated key equals new key")
    check(Constants.WordSub.pairKey(from: "russian - pc", to: "abc") == pair.key,
          "pairKey uses the same normalization")
}

// MARK: - Layout identity (stable ids)

/// Guards the language-switch regression: a layout's *localized* name changes
/// with the system language (`Russian – PC` in English, `Русская — ПК` in
/// Russian), so storing or comparing names silently stopped working the moment
/// the language changed. Storage and comparison go through stable input source
/// ids instead.
func testLayoutIdentityUsesStableIDs() {
    let russian = "com.apple.keylayout.RussianWin"
    let abc = "com.apple.keylayout.ABC"

    check(LayoutPair(from: russian, to: abc) == LayoutPair(from: russian, to: abc),
          "id pairs compare equal")
    check(russian != abc, "distinct layouts have distinct ids")

    // What the `ru` localization actually emits is "Русская — ПК" with a
    // non-breaking space before the dash — folding that is what keeps old
    // name-based values comparable at all.
    check(LayoutPair.normalized("Русская\u{00A0}— ПК") == LayoutPair.normalized("Русская — ПК"),
          "non-breaking space is normalized")
    check(LayoutPair.normalized("Russian – PC") == LayoutPair.normalized("Russian - PC"),
          "en dash folds to hyphen")

    // Storage keys work the same way for ids as they did for names: the key
    // joins the *normalized* halves, so ids differing only in case still fold.
    let pair = LayoutPair(from: russian, to: abc)
    check(LayoutPair.migrateKey("\(russian)|\(abc)") == pair.key,
          "migrated key equals new key for ids")
    check(pair.key == Constants.WordSub.pairKey(from: LayoutPair.normalized(russian),
                                                to: LayoutPair.normalized(abc)),
          "pair key joins the normalized halves")
    check(pair.key == LayoutPair(from: Constants.Default.leftLayoutID,
                                 to: Constants.Default.rightLayoutID).key,
          "default pair key normalizes the same way")
}

// MARK: - Mapper pair options

/// The mapper's From/To pickers must never offer an impossible pair: a mapping
/// always has a source (no "—"), and a target that differs from it.
func testMapperPairOptions() {
    let ru = LayoutRegistry.Layout(id: "com.apple.keylayout.RussianWin", name: "Русская — ПК")
    let abc = LayoutRegistry.Layout(id: "com.apple.keylayout.ABC", name: "ABC")
    let he = LayoutRegistry.Layout(id: "com.apple.keylayout.Hebrew", name: "Иврит")
    let layouts = [ru, abc, he]
    let none = Constants.Default.noneLanguage

    // Source side: every layout, no "—".
    let source = LayoutRegistry.mapperOptions(layouts, excluding: "")
    check(Set(source.map(\.id)) == Set(layouts.map(\.id)),
          "source side lists every layout")
    check(!source.contains { $0.id == none }, "source side never offers \"—\"")

    // Target side: the chosen source is gone, the rest stay.
    let target = LayoutRegistry.mapperOptions(layouts, including: [ru.id], excluding: ru.id)
    check(!target.contains { $0.id == ru.id }, "target side excludes the chosen source")
    check(target.contains { $0.id == abc.id } && target.contains { $0.id == he.id },
          "target side keeps the other layouts")

    // An excluded layout is not smuggled back in as a configured extra.
    check(target.filter { $0.id == ru.id }.count == 0, "extras cannot re-add the excluded layout")

    // A single-layout system leaves nothing to map to: "—" is the answer.
    let degenerate = LayoutRegistry.mapperOptions([ru], including: [ru.id], excluding: ru.id)
    check(degenerate.map(\.id) == [none], "single-layout system falls back to \"—\"")

    // The switcher card keeps "—": a command key may be bound to nothing.
    let switcher = LayoutRegistry.switcherOptions([ru, abc])
    check(switcher.first?.id == none, "switcher options lead with \"—\"")
    check(switcher.map(\.id).filter { $0 == none }.count == 1, "\"—\" appears exactly once")
    check(LayoutRegistry.Layout(id: none, name: none).label == "—",
          "the \"—\" row renders as an em dash, not as a word")
}

// MARK: - Run

testWordMatcher()
testPresetTransform()
testHotkeyCoding()
testLayoutPairNormalization()
testLayoutIdentityUsesStableIDs()
testMapperPairOptions()

if failures == 0 {
    print("✅ All logic tests passed")
    exit(0)
} else {
    print("❌ \(failures) failure(s)")
    exit(1)
}
