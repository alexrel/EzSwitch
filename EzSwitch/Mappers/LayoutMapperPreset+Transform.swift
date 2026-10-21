import Foundation

/// Compiles a preset once per conversion, with explicit extra rules taking
/// priority over regular key mappings in both directions.
struct LayoutMappingApplication {
    private let forward: TextReplacements
    private let reverse: TextReplacements

    init(preset: LayoutMapperPreset) {
        var rules: [String: String] = [:]
        for (source, target) in preset.mapping where !target.isEmpty {
            guard let character = source.first else { continue }
            rules[String(character)] = target
        }
        let extras = preset.extraMappings.filter { !$0.source.isEmpty && !$0.target.isEmpty }
        for extra in extras { rules[extra.source] = extra.target }
        forward = TextReplacements(rules)

        // Sort the ordinary rules to make ambiguous inverses deterministic.
        // Explicit extras win collisions with ordinary target characters.
        var inverse: [String: String] = [:]
        for source in rules.keys.sorted() { inverse[rules[source]!] = source }
        for extra in extras where rules[extra.source] == extra.target {
            inverse[extra.target] = extra.source
        }
        reverse = TextReplacements(inverse)
    }

    func applying(_ text: String) -> String { forward.apply(text) }
    func inverted(_ text: String) -> String { reverse.apply(text) }
    var reversedCharacters: [Character: String] { reverse.characters }
    func forwardPatternScore(_ text: String) -> Int { forward.patternScore(text) }
    func reversePatternScore(_ text: String) -> Int { reverse.patternScore(text) }
}

/// Longest-match replacement in one pass. Replacement output is never fed
/// back into another rule, so explicit targets cannot cascade or loop.
private struct TextReplacements {
    let characters: [Character: String]
    private let patterns: [(source: String, target: String)]

    init(_ rules: [String: String]) {
        var characters: [Character: String] = [:]
        var patterns: [(source: String, target: String)] = []
        for (source, target) in rules where !source.isEmpty && !target.isEmpty {
            if source.count == 1, let character = source.first {
                characters[character] = target
            } else {
                patterns.append((source, target))
            }
        }
        self.characters = characters
        self.patterns = patterns.sorted {
            $0.source.count == $1.source.count ? $0.source < $1.source : $0.source.count > $1.source.count
        }
    }

    func apply(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            if let match = patterns.first(where: { text[index...].hasPrefix($0.source) }) {
                result.append(match.target)
                index = text.index(index, offsetBy: match.source.count)
            } else {
                let character = text[index]
                result.append(characters[character] ?? String(character))
                index = text.index(after: index)
            }
        }
        return result
    }

    func patternScore(_ text: String) -> Int {
        patterns.reduce(0) { score, rule in
            score + (rule.source != rule.target && text.contains(rule.source) ? rule.source.count : 0)
        }
    }
}

extension LayoutMapperPreset {
    /// Single-character inverse for direction detection. Longer targets are
    /// handled by the same longest-match engine used in the live conversion.
    func reversedCharacterMapping() -> [Character: String] {
        LayoutMappingApplication(preset: self).reversedCharacters
    }

    /// Shared by the editor preview, text correction, and dictionary learning.
    /// Extra sources are matched in the original input, before regular keys
    /// can consume them. A saved modifier describes how that source was typed;
    /// converting existing text does not require the modifier to remain held.
    func apply(_ text: String, from fromLayout: String) -> String {
        guard !text.isEmpty else { return "" }
        let application = LayoutMappingApplication(preset: self)
        return LayoutPair.namesMatch(fromLayout, self.fromLayout)
            ? application.applying(text) : application.inverted(text)
    }

    /// Auto-detect the direction for the editor preview, then use exactly the
    /// same conversion as the real text correction.
    func transform(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        let forward = characterMapping()
        let application = LayoutMappingApplication(preset: self)
        let reverse = application.reversedCharacters
        var forwardHits = 0
        var reverseHits = 0
        for character in text {
            let inForward = forward[character] != nil && forward[character] != String(character)
            let inReverse = reverse[character] != nil && reverse[character] != String(character)
            if inForward && !inReverse { forwardHits += 1 }
            if inReverse && !inForward { reverseHits += 1 }
        }
        forwardHits += application.forwardPatternScore(text)
        reverseHits += application.reversePatternScore(text)
        return reverseHits > forwardHits ? application.inverted(text) : application.applying(text)
    }
}
