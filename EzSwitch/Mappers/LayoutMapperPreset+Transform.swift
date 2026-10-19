import Foundation

/// Direction-aware application of a single preset's character map.
///
/// The reverse direction needs longest-match over multi-character targets
/// (`й` → `"QQ"` must invert from `"QQ"`, not from `Q`), so it is built once
/// in the initializer and then applied in a single left-to-right pass.
struct LayoutMappingApplication {
    private let charMap: [Character: String]
    private let multiPatterns: [(pattern: String, replacement: String)]

    init(forward: [Character: String]) {
        var charMap: [Character: String] = [:]
        var patterns: [(String, String)] = []
        for (source, target) in forward {
            if target.count == 1, let first = target.first {
                charMap[first] = String(source)
            } else {
                patterns.append((target, String(source)))
            }
        }
        // A character that starts a multi-char pattern must not also be
        // replaced by the single-char map — longest match wins.
        for start in Set(patterns.map { $0.0.first! }) {
            charMap.removeValue(forKey: start)
        }
        patterns.sort { $0.0.count > $1.0.count }
        self.charMap = charMap
        self.multiPatterns = patterns
    }

    /// Invert the forward map and apply it: single chars map directly, longer
    /// targets are matched greedily longest-first.
    func inverted(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var i = text.startIndex
        let end = text.endIndex
        while i < end {
            var matched = false
            for (pattern, replacement) in multiPatterns {
                let endIdx = text.index(i, offsetBy: pattern.count, limitedBy: end) ?? end
                if text[i..<endIdx] == pattern {
                    result.append(replacement)
                    i = endIdx
                    matched = true
                    break
                }
            }
            if !matched {
                let char = text[i]
                result.append(charMap[char] ?? String(char))
                i = text.index(after: i)
            }
        }
        return result
    }
}

extension LayoutMapperPreset {

    /// Inverse of `characterMapping()` for the single-character targets.
    ///
    /// Multi-character targets cannot be inverted character-by-character, so
    /// they are skipped here — use `inverted(_:)` (via `apply(_:from:)`) when
    /// they matter, e.g. in word substitution and text transformation.
    func reversedCharacterMapping() -> [Character: String] {
        var reversed: [Character: String] = [:]
        for (source, target) in characterMapping() where target.count == 1 {
            if let first = target.first {
                reversed[first] = String(source)
            }
        }
        return reversed
    }

    /// Apply this preset's mapping to `text`, typed in `fromLayout`.
    ///
    /// Shared direction-aware mapping for word substitution and text transformation.
    /// The editor preview uses transform(_:) to choose its direction automatically.
    /// The forward direction maps character by character; the reverse inverts
    /// with longest-match so multi-character targets survive.
    func apply(_ text: String, from fromLayout: String) -> String {
        guard !text.isEmpty else { return "" }
        let forward = characterMapping()
        if LayoutPair.namesMatch(fromLayout, self.fromLayout) {
            var result = ""
            result.reserveCapacity(text.count)
            for char in text {
                result.append(forward[char] ?? String(char))
            }
            return result
        }
        return LayoutMappingApplication(forward: forward).inverted(text)
    }

    /// Transform `text` in this preset's direction, auto-detecting which side
    /// the text is written in.
    ///
    /// The direction is chosen by counting characters that only occur in the
    /// forward map versus only in the reverse map; ties go forward. Extra
    /// mappings are applied afterwards as plain substring replacements.
    func transform(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        let forward = characterMapping()
        let reverse = reversedCharacterMapping()

        var forwardHits = 0
        var reverseHits = 0
        for ch in text {
            let inForward = forward[ch] != nil && forward[ch] != String(ch)
            let inReverse = reverse[ch] != nil && reverse[ch] != String(ch)
            if inForward && !inReverse { forwardHits += 1 }
            if inReverse && !inForward { reverseHits += 1 }
        }

        var result: String
        if reverseHits > forwardHits {
            result = LayoutMappingApplication(forward: forward).inverted(text)
        } else {
            var out = ""
            out.reserveCapacity(text.count)
            for ch in text { out.append(forward[ch] ?? String(ch)) }
            result = out
        }

        for extra in extraMappings where !extra.source.isEmpty && !extra.target.isEmpty {
            result = result.replacingOccurrences(of: extra.source, with: extra.target)
        }
        return result
    }
}
