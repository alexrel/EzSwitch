import Foundation

extension LayoutMapperPreset {

    /// Inverse of `characterMapping()` for the single-character targets.
    ///
    /// Multi-character targets cannot be inverted character-by-character, so
    /// they are skipped here — the reverse direction for those is handled by
    /// `TextTransformer.applyReverse` via longest-match.
    func reversedCharacterMapping() -> [Character: String] {
        var reversed: [Character: String] = [:]
        for (source, target) in characterMapping() where target.count == 1 {
            if let first = target.first {
                reversed[first] = String(source)
            }
        }
        return reversed
    }

    /// Mapping restricted to the direction `fromLayout → toLayout`.
    /// Returns the forward map when `fromLayout` is this preset's source,
    /// the reversed map otherwise.
    func mapping(from fromLayout: String) -> [Character: String] {
        fromLayout == self.fromLayout ? characterMapping() : reversedCharacterMapping()
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

        let active = reverseHits > forwardHits ? reverse : forward
        var result = ""
        result.reserveCapacity(text.count)
        for ch in text {
            result.append(active[ch] ?? String(ch))
        }

        for extra in extraMappings where !extra.source.isEmpty && !extra.target.isEmpty {
            result = result.replacingOccurrences(of: extra.source, with: extra.target)
        }
        return result
    }
}
