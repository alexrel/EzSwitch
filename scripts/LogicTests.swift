import Foundation
import Combine
import AppKit
import ApplicationServices

// Standalone harness for mapping, matching, hotkey, and picker logic.
// The app has no XCTest target; run the wrapper to compile these sources
// together and copy the harness to main.swift for its top-level test calls:
//
//   zsh scripts/run-logic-tests.sh
//
// These checks do not cover settings migration or live keyboard/clipboard flows.

// Store tests use explicit files; never initialize the app's event tap or login item.
final class SettingsManager {
    static let shared = SettingsManager()
    private(set) var seedLayoutReads = 0
    var leftCommandLayout: String {
        seedLayoutReads += 1
        return Constants.Default.noneLanguage
    }
    var rightCommandLayout: String { Constants.Default.noneLanguage }
    func setSelectedPresetId(_ id: String?, for from: String, _ to: String) {}
}

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

    // Extra rules match original input, before the ordinary keys consume it.
    var withExtra = preset
    withExtra.extraMappings = [
        LayoutMapperPreset.ExtraMapping(source: "привет", target: "HELLO")
    ]
    equal(withExtra.transform("привет"), "HELLO", "extra mapping matches the original input")
    equal(withExtra.apply("привет", from: "Russian – PC"), "HELLO", "live conversion uses the same extra rule as preview")
    equal(withExtra.apply("HELLO", from: "ABC"), "привет", "extra text rule reverses with longest-match")

    // apply(_:from:) returns the right side for the requested direction.
    equal(preset.apply("й", from: "Russian – PC"), "q", "forward mapping side")
    equal(preset.apply("q", from: "ABC"), "й", "reversed mapping side")
    // The reverse direction inverts with longest-match, so multi-char targets
    // survive instead of being dropped.
    equal(multi.apply("QQ", from: "ABC"), "я", "reverse inverts multi-char targets")
    equal(preset.apply("й п", from: "Russian – PC"), "q g", "forward maps char by char")
    equal(preset.apply("q g", from: "ABC"), "й п", "reverse maps char by char")
}

func testExtraMappings() {
    var preset = makePreset()
    preset.extraMappings = [.init(source: "Ђ", target: "¸", modifier: .shiftOption)]
    equal(preset.apply("Ђ", from: preset.fromLayout), "¸", "Shift+Option source is converted in the real pipeline")
    equal(preset.transform("Ђ"), "¸", "Shift+Option source works in preview")
    equal(preset.apply("¸", from: preset.toLayout), "Ђ", "Shift+Option rule reverses")
    equal(preset.transform("¸"), "Ђ", "preview detects the reverse extra rule")
    equal(preset.apply("йЂ п", from: preset.fromLayout), "q¸ g", "extra rules coexist with ordinary mapping")

    preset.extraMappings = [
        .init(source: "п", target: "ZZ", modifier: .none),
        .init(source: "Ж", target: "🙂", modifier: .shift),
        .init(source: "џ", target: "XYZ", modifier: .option),
        .init(source: "", target: "ignored"),
        .init(source: "й", target: "")
    ]
    preset.mapping["я"] = "ZZ"
    equal(preset.apply("пЖџй", from: preset.fromLayout), "ZZ🙂XYZq", "all modifier variants and Unicode targets work; incomplete rules are ignored")
    equal(preset.apply("ZZ🙂XYZ", from: preset.toLayout), "пЖџ", "explicit extras win ambiguous inverses")
    equal(preset.transform("XYZ"), "џ", "preview recognizes multi-character extra targets")

    preset.extraMappings = [.init(source: "п", target: "й"), .init(source: "й", target: "!"), .init(source: "п", target: "ц")]
    equal(preset.apply("пй", from: preset.fromLayout), "ц!", "later duplicate extras win and targets are not transformed again")
    equal(preset.transform("пй"), "ц!", "preview never cascades extra replacements")

    preset.mapping = ["й": "QQ", "п": "Q"]
    preset.extraMappings = []
    equal(preset.apply("QQQ", from: preset.toLayout), "йп", "short reverse fallback survives an incomplete longer match")
    equal(preset.transform("QQ"), "й", "preview recognizes multi-character ordinary targets")

    do {
        preset.extraMappings = [.init(source: "Ђ", target: "¸", modifier: .shiftOption)]
        let restored = try JSONDecoder().decode(LayoutMapperPreset.self, from: JSONEncoder().encode(preset))
        equal(restored.extraMappings, preset.extraMappings, "extra source, target and modifier survive persistence")
        equal(restored.apply("Ђ", from: restored.fromLayout), "¸", "saved extra rule remains effective after loading")
    } catch { check(false, "extra mapping persistence: \(error)") }
}

// MARK: - Hotkey

func testExtraMappingSourceDetection() {
    let ru = "com.apple.keylayout.RussianWin"
    let abc = "com.apple.keylayout.ABC"
    let he = "com.apple.keylayout.Hebrew"
    let candidates = [ru, abc, he]
    var preset = LayoutMapperPreset(name: "extra", fromLayout: ru, toLayout: abc,
                                    mapping: ["п": "g"],
                                    extraMappings: [.init(source: "Ђ", target: "¸", modifier: .shiftOption)])
    // Deliberately exclude Option characters, just like the real base cache.
    let characters: [String: Set<Character>] = [ru: Set("привет"), abc: Set("hello"), he: Set("שלום")]
    func detect(_ text: String, current: String, presets: [LayoutMapperPreset]) -> String {
        TransformSourceDetection.layout(for: text, current: current, candidates: candidates,
                                        activePresets: presets, charactersProduced: { characters[$0] ?? [] })
    }
    for current in candidates {
        let source = detect("Ђ", current: current, presets: [preset])
        equal(source, ru, "extra source is recognized with \(current) active")
        equal(preset.apply("Ђ", from: source), "¸", "detected direction applies the extra rule")
        let reverseSource = detect("¸", current: current, presets: [preset])
        equal(reverseSource, abc, "extra punctuation target is recognized with \(current) active")
        equal(preset.apply("¸", from: reverseSource), "Ђ", "detected reverse direction applies the extra rule")
    }
    equal(detect("123 !?", current: he, presets: [preset]), he, "unmapped shared punctuation preserves current layout")
    equal(detect("hello", current: ru, presets: [preset]), abc, "ordinary letter detection is preserved")
    equal(detect("Ђ", current: abc, presets: []), abc, "inactive preset extras do not influence detection")
    preset.extraMappings = [.init(source: "Ђ", target: "XYZ", modifier: .shiftOption)]
    equal(detect("XYZ", current: ru, presets: [preset]), abc, "multi-character extra targets identify the reverse source")
    preset.extraMappings = [.init(source: "Ђ", target: "")]
    equal(detect("Ђ", current: abc, presets: [preset]), abc, "incomplete extra rules provide no evidence")
}

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

/// Checks ID pair keys and legacy name normalization. It does not exercise
/// migration of saved settings after a system language change.
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

/// Checks source/target options, exclusions, and the single-layout fallback.
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

func testLiveLayoutNames() {
    func expectedName(for id: String, translated: String) -> String {
        if #available(macOS 15.4, *) { return translated }
        guard let source = LayoutRegistry.source(forID: id) else { return id }
        return KeyboardLayoutUtility.localizedName(of: source) ?? id
    }
    let localization = AppLocalization.shared
    let original = localization.language
    defer { localization.apply(original) }

    let hebrew = "com.apple.keylayout.Hebrew"
    let russian = "com.apple.keylayout.RussianWin"
    let expectedHebrew: [(AppLanguage, String)] = [(.he, "עברית"), (.ru, "Иврит"), (.uk, "Іврит"), (.en, "Hebrew"), (.he, "עברית")]
    let originalIDs = Set(LayoutRegistry.available().map(\.id))
    for (language, translated) in expectedHebrew {
        let expected = expectedName(for: hebrew, translated: translated)
        localization.apply(language)
        let layouts = LayoutRegistry.available()
        equal(Set(layouts.map(\.id)), originalIDs, "changing language preserves available layout IDs")
        equal(LayoutRegistry.displayName(forID: hebrew), expected, "layout display name follows \(language) in the same process")
        if let row = layouts.first(where: { $0.id == hebrew }) {
            equal(row.label, expected, "picker rows use the current language")
        }
        let extra = LayoutRegistry.switcherOptions([], including: [hebrew])
        equal(extra.first(where: { $0.id == hebrew })?.label, expected, "configured extra layouts use the current language")
    }
    localization.apply(.ru)
    equal(LayoutPair.normalized(LayoutRegistry.displayName(forID: russian)),
          LayoutPair.normalized(expectedName(for: russian, translated: "Русская — ПК")), "Russian PC retains its variant in the displayed name")
    equal(LayoutRegistry.displayName(forID: "com.example.removed-layout"), "com.example.removed-layout", "unknown layouts retain their stored identity")
    equal(LayoutRegistry.displayName(forID: Constants.Default.noneLanguage), Constants.Default.noneLanguage, "the unset layout is unchanged")
}

func testPresetDisplayNames() {
    let localization = AppLocalization.shared
    let original = localization.language
    defer { localization.apply(original) }
    let ru = "com.apple.keylayout.RussianWin"
    let abc = "com.apple.keylayout.ABC"
    let oldName = "Русская — ПК ↔ ABC (auto)"
    var automatic = LayoutMapperPreset(name: oldName, fromLayout: ru, toLayout: abc, mapping: ["й": "q"])
    equal(automatic.resolvedNameStyle, .automatic, "legacy generated title is recognized by its exact pair")
    for language in [AppLanguage.en, .he, .ru, .uk, .de, .fr, .es, .pl, .en] {
        localization.apply(language)
        let expected = "\(LayoutRegistry.displayName(forID: ru)) ↔ \(LayoutRegistry.displayName(forID: abc))"
        // Foundation isolates interpolated layout labels in RTL strings.
        let visibleTitle = automatic.displayName.replacingOccurrences(of: "\u{2068}", with: "")
            .replacingOccurrences(of: "\u{2069}", with: "")
        check(visibleTitle.hasPrefix(expected), "generated title follows \(language) without restarting")
        equal(automatic.name, oldName, "display localization never rewrites the stored title")
        equal(automatic.mapping, ["й": "q"], "display localization preserves mapping data")
    }
    let custom = LayoutMapperPreset(name: "My ↔ favorite (auto)", fromLayout: ru, toLayout: abc)
    equal(custom.resolvedNameStyle, .custom, "arbitrary user name with an auto suffix stays custom")
    let exactCustom = LayoutMapperPreset(name: oldName, fromLayout: ru, toLayout: abc, nameStyle: .custom)
    equal(exactCustom.displayName, oldName, "an explicitly custom name is preserved even when it looks generated")
    let pair = LayoutMapperPreset(name: "Russian – PC → ABC", fromLayout: ru, toLayout: abc)
    equal(pair.resolvedNameStyle, .pair, "legacy default pair-only title is recognized")
    automatic.nameStyle = automatic.resolvedNameStyle
    do {
        let restored = try JSONDecoder().decode(LayoutMapperPreset.self, from: JSONEncoder().encode(automatic))
        equal(restored.nameStyle, .automatic, "generated-name metadata survives persistence")
        equal(restored.name, oldName, "metadata migration retains the stored title")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(automatic)) as! [String: Any]
        legacy.removeValue(forKey: "nameStyle")
        let decoded = try JSONDecoder().decode(LayoutMapperPreset.self, from: JSONSerialization.data(withJSONObject: legacy))
        equal(decoded.nameStyle, nil, "old presets decode without name metadata")
        equal(decoded.resolvedNameStyle, .automatic, "old decoded presets retain dynamic generated titles")
    } catch { check(false, "preset name persistence: \(error)") }
}

func testPresetFileSafety() {
    let fm = FileManager.default
    let directory = fm.temporaryDirectory.appendingPathComponent("EzSwitch.StoreTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? fm.removeItem(at: directory) }
    do {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("presets.json")
        let first = LayoutMapperPreset(name: "A ↔ B (auto)", fromLayout: "A", toLayout: "B", mapping: ["a": "b"])
        var different = LayoutMapperPreset(name: first.name, fromLayout: "A", toLayout: "B", mapping: ["a": "c"])
        different.extraMappings = [.init(source: "Ђ", target: "¸", modifier: .shiftOption)]
        let identical = LayoutMapperPreset(name: first.name, fromLayout: "A", toLayout: "B", mapping: first.mapping)
        let originals = [first, different, identical]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(originals).write(to: file)

        let store = MapperStore(fileURL: file)
        equal(store.snapshot().map(\.id), originals.map(\.id), "same-name presets keep every ID, including identical rules")
        equal(store.preset(byID: different.id)?.extraMappings, different.extraMappings, "extra rules survive loading")
        let frozen = store.snapshot()
        different.mapping["a"] = "edited"
        store.save(different)
        equal(frozen[1].mapping["a"], "c", "a captured store snapshot is independent of later edits")
        store.flush()
        let reloaded = MapperStore(fileURL: file)
        equal(reloaded.snapshot().map(\.id), originals.map(\.id), "name migration preserves IDs on disk")
        equal(reloaded.preset(byID: different.id)?.mapping["a"], "edited", "flush saves the latest edit")

        let corruptFile = directory.appendingPathComponent("corrupt.json")
        let corruptBytes = Data("[{ incomplete JSON".utf8)
        try corruptBytes.write(to: corruptFile)
        let seedReads = SettingsManager.shared.seedLayoutReads
        let damagedStore = MapperStore(fileURL: corruptFile)
        check(damagedStore.snapshot().isEmpty, "an unreadable file never auto-seeds a preset")
        check(damagedStore.presets(for: first.pair).isEmpty, "reading a damaged store does not seed it")
        damagedStore.flush()
        equal(SettingsManager.shared.seedLayoutReads, seedReads, "load failure never invokes automatic seeding")
        equal(try Data(contentsOf: corruptFile), corruptBytes, "opening and flushing leave the unreadable original intact")
        equal(try fm.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".bak") }.count, 0,
              "reading alone does not create recovery files")

        let replacement = damagedStore.createPreset(name: "Recovered", from: "A", to: "B", mapping: ["x": "y"])
        damagedStore.flush()
        let backups = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "bak" }
        equal(backups.count, 1, "an explicit save backs up the unreadable file once")
        if let backup = backups.first {
            equal(try Data(contentsOf: backup), corruptBytes, "backup preserves the exact original bytes")
        }
        equal(MapperStore(fileURL: corruptFile).snapshot().map(\.id), [replacement.id], "explicit edits remain persistable after backup")
        damagedStore.save(replacement)
        damagedStore.flush()
        equal(try fm.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".bak") }.count, 1,
              "later saves retain the original backup")

        let blockedDirectory = directory.appendingPathComponent("blocked", isDirectory: true)
        try fm.createDirectory(at: blockedDirectory, withIntermediateDirectories: true)
        let blockedFile = blockedDirectory.appendingPathComponent("presets.json")
        try corruptBytes.write(to: blockedFile)
        let blockedStore = MapperStore(fileURL: blockedFile)
        // Move the unreadable source away before saving to force a backup failure.
        let retainedFile = blockedDirectory.appendingPathComponent("retained.json")
        try fm.moveItem(at: blockedFile, to: retainedFile)
        blockedStore.save(first)
        blockedStore.flush()
        check(!fm.fileExists(atPath: blockedFile.path), "a failed backup aborts the write")
        equal(try Data(contentsOf: retainedFile), corruptBytes, "backup failure preserves the old bytes")
        try fm.moveItem(at: retainedFile, to: blockedFile)
        blockedStore.save(first)
        blockedStore.flush()
        equal(MapperStore(fileURL: blockedFile).snapshot().map(\.id), [first.id], "saving can retry after a backup failure")

        let newFile = directory.appendingPathComponent("new/subfolder/presets.json")
        let newStore = MapperStore(fileURL: newFile)
        check(newStore.snapshot().isEmpty, "an absent file starts empty when no layout pair is configured")
        newStore.save(first)
        newStore.flush()
        equal(MapperStore(fileURL: newFile).snapshot().map(\.id), [first.id], "first save creates the missing parent directory")
    } catch {
        check(false, "preset file safety: \(error)")
    }
}

func testTransformSnapshot() {
    let pair = LayoutPair(from: "A", to: "B")
    let first = LayoutMapperPreset(name: "First", fromLayout: "A", toLayout: "B", mapping: ["Ђ": "other"])
    let selected = LayoutMapperPreset(name: "Selected", fromLayout: "A", toLayout: "B",
                                      extraMappings: [.init(source: "Ђ", target: "¸", modifier: .shiftOption)])
    let bridge = LayoutMapperPreset(name: "Bridge", fromLayout: "B", toLayout: "C", mapping: ["¸": "z"])
    var presets = [first, selected, bridge]
    let inverseKey = LayoutPair(from: "B", to: "A").key
    var selectedIDs = [inverseKey: selected.id]
    var languages = ["A", "B", "", Constants.Default.noneLanguage]
    var shouldSwitch = true
    let snapshot = TransformSnapshot(presets: presets, selectedPresetIDs: selectedIDs,
                                     primaryLanguages: languages, switchLayoutAfterTransform: shouldSwitch)
    equal(snapshot.activePresets.map(\.id), [selected.id, bridge.id], "snapshot honors selected ID in the inverse pair key")
    equal(snapshot.primaryLanguages, ["A", "B"], "snapshot excludes unset layouts")
    equal(snapshot.transform(text: "Ђ", from: "A", to: "B"), "¸", "selected extra mapping is applied")
    equal(snapshot.transform(text: "¸", from: "B", to: "A"), "Ђ", "selected rules also apply in reverse")
    equal(snapshot.transform(text: "Ђ", from: "A", to: "C"), "z", "bridge hops use the selected rules")
    equal(snapshot.transform(text: "z", from: "C", to: "A"), "Ђ", "bridge rules reverse consistently")
    equal(snapshot.transform(text: "Ђ", from: "A", to: "missing"), nil, "missing paths do not transform")

    presets[1].extraMappings[0].target = "new"
    selectedIDs[inverseKey] = first.id
    languages = ["C", "B"]
    shouldSwitch = false
    let next = TransformSnapshot(presets: presets, selectedPresetIDs: selectedIDs,
                                 primaryLanguages: languages, switchLayoutAfterTransform: shouldSwitch)
    let inFlightResult = DispatchQueue.global().sync {
        snapshot.transform(text: "Ђ", from: "A", to: "B")
    }
    equal(inFlightResult, "¸", "background transformation keeps the captured rules after edits on main")
    equal(snapshot.primaryLanguages, ["A", "B"], "in-flight snapshot keeps its original layouts")
    check(snapshot.switchLayoutAfterTransform, "in-flight snapshot keeps its layout-switch preference")
    equal(next.transform(text: "Ђ", from: "A", to: "B"), "other", "the next request picks up the newly selected preset")
    check(next != snapshot, "changed settings invalidate a previously planned cycle")
    let edited = TransformSnapshot(presets: presets, selectedPresetIDs: [pair.key: selected.id],
                                   primaryLanguages: ["A", "B"], switchLayoutAfterTransform: true)
    equal(edited.transform(text: "Ђ", from: "A", to: "B"), "new", "the next request picks up edited extra rules")
    let fallback = TransformSnapshot(presets: presets, selectedPresetIDs: [pair.key: "deleted"],
                                     primaryLanguages: [], switchLayoutAfterTransform: false)
    equal(fallback.activePresets.first?.id, first.id, "an absent selected preset falls back to the first one")
    let detected = TransformSourceDetection.layout(for: "Ђ", current: "C", candidates: ["A", "B", "C"],
                                                   activePresets: snapshot.activePresets, charactersProduced: { _ in [] })
    equal(detected, "A", "source detection uses the same snapshotted extra rules")
    let cyclic = TransformSnapshot(presets: [
        LayoutMapperPreset(name: "AB", fromLayout: "A", toLayout: "B", mapping: ["a": "b"]),
        LayoutMapperPreset(name: "BC", fromLayout: "B", toLayout: "C", mapping: ["b": "c"]),
        LayoutMapperPreset(name: "CA", fromLayout: "C", toLayout: "A", mapping: ["c": "a"]),
        LayoutMapperPreset(name: "AD", fromLayout: "A", toLayout: "D", mapping: ["x": "d"]),
        LayoutMapperPreset(name: "BD", fromLayout: "B", toLayout: "D", mapping: ["x": "d"]),
        LayoutMapperPreset(name: "CD", fromLayout: "C", toLayout: "D", mapping: ["x": "d"])
    ], selectedPresetIDs: [:], primaryLanguages: ["A", "D"], switchLayoutAfterTransform: false)
    equal(cyclic.transform(text: "a", from: "A", to: "D"), nil, "cyclic bridge paths stop at the depth limit")
}

func testAppLanguagePreference() {
    let suite = "EzSwitch.LanguageTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    equal(AppLanguage.stored(in: defaults), .system, "interface follows system by default")
    for language in AppLanguage.allCases where language != .system {
        language.save(in: defaults)
        equal(AppLanguage.stored(in: defaults), language, "\(language) selection persists")
        equal(defaults.stringArray(forKey: "AppleLanguages"), [language.rawValue], "\(language) override survives relaunch")
    }
    AppLanguage.he.save(in: defaults)
    equal(AppLanguage.stored(in: defaults), .he, "Hebrew language selection persists")
    equal(defaults.stringArray(forKey: "AppleLanguages"), ["he"], "language override is available at next launch")
    AppLanguage.uk.save(in: defaults)
    equal(defaults.stringArray(forKey: "AppleLanguages"), ["uk"], "changing language replaces previous override")
    AppLanguage.system.save(in: defaults)
    equal(AppLanguage.stored(in: defaults), .system, "system selection persists")
    check(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil,
          "system selection removes per-app language override")
}

func testLiveLocalization() {
    let bundleURL = URL(fileURLWithPath: CommandLine.arguments[0])
        .deletingLastPathComponent().appendingPathComponent("LocalizationTests.bundle")
    guard let resources = Bundle(url: bundleURL) else {
        check(false, "localization test bundle exists")
        return
    }
    var systemLanguages = ["uk-UA", "en-US"]
    let localization = AppLocalization(language: .en, resourceBundle: resources, systemLanguages: { systemLanguages })
    var changes: [String] = []
    let observation = localization.$languageCode.dropFirst().sink { changes.append($0) }
    defer { observation.cancel() }

    equal(localization.string("General"), "General", "initial English lookup")
    localization.apply(.ru)
    equal(localization.string("General"), "Основные", "Russian applies without restarting")
    let name = "My preset"
    let count = 7
    equal(localization.string("Delete “\(name)”"), "Удалить «My preset»", "interpolated names survive translation")
    equal(localization.string("This will clear all \(count) mapped keys in “\(name)”."),
          "При этом будут очищены все 7 сопоставленные клавиши в «My preset».", "integer and string interpolation retain their types")
    localization.apply(.uk)
    equal(localization.string("General"), "Основні", "Ukrainian applies in the same process")
    localization.apply(.he)
    equal(localization.string("General"), "כללי", "Hebrew applies in the same process")
    let from = "רוסית"
    let to = "ABC"
    equal(localization.string("\(from) ↔ \(to) (auto)"), "\u{2068}רוסית\u{2069} ↔ \u{2068}ABC\u{2069} (אוטומטי)", "automatic preset suffix localizes and isolates mixed-direction layout names")
    check(localization.isRightToLeft, "Hebrew enables RTL")
    localization.apply(.en)
    equal(localization.string("General"), "General", "switching back does not reuse cached translation")
    check(!localization.isRightToLeft, "returning to English restores LTR")
    equal(localization.string("Missing key: \(name)"), "Missing key: My preset", "missing keys preserve default interpolation")

    localization.apply(.system)
    equal(localization.languageCode, "uk", "system choice ignores the previously selected app language")
    systemLanguages = ["he-IL"]
    localization.refreshSystemLanguage()
    equal(localization.languageCode, "he", "system-language preference can refresh live")
    localization.apply(.ru)
    systemLanguages = ["en-US"]
    localization.refreshSystemLanguage()
    equal(localization.languageCode, "ru", "system changes do not replace an explicit choice")
    localization.apply(.ru)
    equal(changes, ["ru", "uk", "he", "en", "uk", "he", "ru"], "only actual language changes publish a UI update")

    let addedLanguages: [(AppLanguage, String, String, String, String)] = [
        (.de, "de-AT", "Allgemein", "„My preset“ löschen", "Alle 7 Tastenzuordnungen in „My preset“ werden geleert."),
        (.fr, "fr-CA", "Général", "Supprimer « My preset »", "Les 7 correspondances de touches de « My preset » seront effacées."),
        (.es, "es-MX", "General", "Eliminar «My preset»", "Se vaciarán las 7 asignaciones de teclas de «My preset»."),
        (.pl, "pl-PL", "Ogólne", "Usuń „My preset”", "Wszystkie przypisania klawiszy (7) w „My preset” zostaną wyczyszczone.")
    ]
    for (language, regionalCode, general, delete, clear) in addedLanguages {
        localization.apply(language)
        equal(localization.string("General"), general, "\(language) applies without restarting")
        equal(localization.string("Delete “\(name)”"), delete, "\(language) preserves interpolated names")
        equal(localization.string("This will clear all \(count) mapped keys in “\(name)”."), clear,
              "\(language) preserves integer and string interpolation")
        check(!localization.isRightToLeft, "\(language) uses LTR")
        equal(AppLocalization.resolve(.system, systemLanguages: [regionalCode, "en-US"]), language.rawValue,
              "\(regionalCode) selects the supported base language")
    }

    equal(AppLocalization.resolve(.system, systemLanguages: ["ja-JP", "uk-UA"]), "uk", "supported secondary system language is preferred")
    equal(AppLocalization.resolve(.system, systemLanguages: ["ja-JP"]), "en", "unsupported language falls back to English")
    equal(AppLocalization.resolve(.system, systemLanguages: []), "en", "empty system preferences fall back to English")
    equal(AppLocalization.resolve(.en, systemLanguages: ["he-IL"]), "en", "explicit choice ignores system preferences")
}

func testPopoverBackground() {
    for (appearance, expected) in [(NSAppearance.Name.aqua, [0.93, 0.95, 1.0]),
                                   (.darkAqua, [0.16, 0.18, 0.23])] {
        let view = PopoverBackgroundView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.appearance = NSAppearance(named: appearance)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 100,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                           isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            check(false, "popover background bitmap can be created")
            continue
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        let x = AppLocalization.shared.isRightToLeft ? 99 : 0
        guard let top = bitmap.colorAt(x: x, y: 0)?.usingColorSpace(.sRGB),
              let below = bitmap.colorAt(x: x, y: 12)?.usingColorSpace(.sRGB) else {
            check(false, "popover background pixels can be read")
            continue
        }
        check(abs(top.redComponent - expected[0]) < 0.02 && abs(top.greenComponent - expected[1]) < 0.02
              && abs(top.blueComponent - expected[2]) < 0.02, "native background uses the existing theme colors")
        equal(top.alphaComponent, 1, "native background fills the arrow region opaquely")
        check(abs(top.redComponent - below.redComponent) < 0.02, "arrow and body share a continuous gradient")
    }
}

func testTerminalInput() {
    var buffer = TypedWordBuffer()
    for scalar in "ghbdtn".unicodeScalars { buffer.append(scalar) }
    equal(buffer.text, "ghbdtn", "manual correction has a word without dictionary matching")
    buffer.append(" ")
    buffer.append(" ")
    equal(buffer.text, "ghbdtn  ", "last word retains trailing spaces for explicit correction")
    equal(buffer.currentWord, "", "extra spaces do not repeat automatic substitution")
    buffer.backspace()
    equal(buffer.text, "ghbdtn ", "backspace first removes the trailing space")
    buffer.append("п")
    buffer.append("ш")
    buffer.append("е")
    equal(buffer.currentWord, "пше", "a new word excludes the previous word and spaces")
    equal(WordMatcher.findMatch(word: buffer.currentWord, in: ["пше": "git"])?.replacement,
          "git", "buffered terminal input uses the existing dictionary matcher")
    buffer.backspace()
    equal(buffer.text, "пш", "backspace removes one Cyrillic character")
    buffer.reset()
    equal(buffer.text, "", "cursor or focus changes forget the old word")
    buffer.replace(with: "שלום")
    equal(buffer.text, "שלום", "a replacement can be corrected again")
    buffer.append("\t")
    equal(buffer.text, "", "completion invalidates the known text")
    buffer.replace(with: "git")
    buffer.append("\r")
    equal(buffer.text, "", "submission invalidates the known text")
    for token in ["cfvb[", ";er", "ghbdtn,", "[", "<"] {
        buffer.replace(with: token)
        equal(buffer.text, token, "manual correction retains punctuation that can map to letters")
        buffer.append(" ")
        equal(buffer.text, token + " ", "manual correction retains punctuation before trailing spaces")
        buffer.backspace()
        equal(buffer.text, token, "backspace restores the complete punctuation-containing token")
    }
    buffer.replace(with: "one,two")
    equal(buffer.currentWord, "two", "dictionary matching still starts after punctuation")
    buffer.backspace()
    equal(buffer.currentWord, "tw", "backspace updates the dictionary word after punctuation")
    buffer.replace(with: "word,")
    equal(buffer.currentWord, "", "punctuation does not retrigger dictionary matching")
    buffer.backspace()
    equal(buffer.currentWord, "word", "backspacing punctuation restores the dictionary word")
    buffer.append(" ")
    buffer.append("x")
    equal(buffer.text, "x", "a new token does not erase the previous token during correction")
    var preset = makePreset()
    preset.mapping["х"] = "["
    buffer.replace(with: "b[  ")
    let corrected = preset.apply(buffer.text, from: "ABC")
    equal(corrected, "их  ", "terminal correction maps the complete token and preserves spaces")
    buffer.replace(with: corrected)
    equal(preset.apply(buffer.text, from: "Russian – PC"), "b[  ", "repeated correction can restore punctuation")
    preset.mapping["у"] = "e"
    preset.mapping["д"] = "l"
    preset.mapping["щ"] = "o"
    buffer.replace(with: "руддщ")
    equal(preset.apply(buffer.text, from: "Russian – PC"), "hello", "reported iTerm input converts without dictionary matching")
    for separator in " .,/;:\t\n\r".unicodeScalars {
        check(TypedWordBuffer.isSeparator(separator), "existing auto-replacement separators remain supported")
    }
    check(AppConfigRegistry.isTerminal(bundleID: "com.apple.Terminal"), "recognizes Terminal case-insensitively")
    check(AppConfigRegistry.isTerminal(bundleID: "com.googlecode.iterm2"), "recognizes iTerm")
    check(!AppConfigRegistry.isTerminal(bundleID: "com.microsoft.VSCode"), "editor text fields keep their existing correction path")
    check(!AppConfigRegistry.isTerminal(bundleID: nil), "unknown apps do not use terminal deletion")
    check(TerminalInput.isSafeReplacement("привет שלום git --help"), "ordinary Unicode and spaces may be pasted")
    for separator in ["\n", "\r", "\t"] {
        check(TerminalInput.replaysSeparator(separator), "Enter and Tab retain their terminal actions")
    }
    for separator in [" ", ".", "/", "|", ";"] {
        check(!TerminalInput.replaysSeparator(separator), "punctuation is pasted as typed even if the layout changes")
    }
    for unsafe in ["", "git\n", "git\r", "git\t", "git\u{1B}[A", "git\u{7F}", "git\u{2028}"] {
        check(!TerminalInput.isSafeReplacement(unsafe), "mapping cannot introduce terminal control input")
    }
}

func testAccessibilitySelection() {
    let element = AXUIElementCreateApplication(getpid())
    let selection = AccessibilityTextSelection(element: element, text: "ghbdtn", range: CFRange(location: 2, length: 6))
    check(selection.matches(selection), "unchanged modal selection may be replaced")
    check(!selection.matches(AccessibilityTextSelection(element: AXUIElementCreateApplication(0), text: selection.text, range: selection.range)),
          "changed focus cancels modal replacement")
    check(!selection.matches(AccessibilityTextSelection(element: element, text: "руддщ", range: selection.range)),
          "edited text cancels modal replacement")
    check(!selection.matches(AccessibilityTextSelection(element: element, text: selection.text, range: CFRange(location: 10, length: 6))),
          "moving selection to an identical word cancels modal replacement")
    check(!selection.matches(AccessibilityTextSelection(element: element, text: selection.text, range: CFRange(location: 2, length: 7))),
          "changed selection length cancels modal replacement")
}

testAccessibilitySelection()
testPopoverBackground()
testTerminalInput()
testAppLanguagePreference()
testPresetFileSafety()
testTransformSnapshot()
testLiveLocalization()
testLiveLayoutNames()
testPresetDisplayNames()
testWordMatcher()
testPresetTransform()
testExtraMappings()
testExtraMappingSourceDetection()
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
