import Foundation

/// Detects the source of existing text using ordinary layout characters and
/// the extra rules from the active presets. Explicit rule targets also count,
/// including punctuation, so the reverse conversion can find its source.
enum TransformSourceDetection {
    static func layout(
        for text: String,
        current: String,
        candidates: [String],
        activePresets: [LayoutMapperPreset],
        charactersProduced: (String) -> Set<Character>
    ) -> String {
        func score(_ layout: String) -> Int {
            guard !layout.isEmpty, layout != Constants.Default.noneLanguage else { return 0 }
            let ordinary = charactersProduced(layout)
            var extraCharacters = Set<Character>()
            var extraPatterns = Set<String>()
            for preset in activePresets {
                let isSource = LayoutPair.namesMatch(layout, preset.fromLayout)
                let isTarget = LayoutPair.namesMatch(layout, preset.toLayout)
                guard isSource || isTarget else { continue }
                for rule in preset.extraMappings where !rule.source.isEmpty && !rule.target.isEmpty && rule.source != rule.target {
                    let input = isSource ? rule.source : rule.target
                    if input.count == 1, let character = input.first {
                        extraCharacters.insert(character)
                    } else {
                        extraPatterns.insert(input)
                    }
                }
            }
            let characterScore = text.reduce(0) { score, character in
                score + ((character.isLetter && ordinary.contains(character)) || extraCharacters.contains(character) ? 1 : 0)
            }
            return extraPatterns.reduce(characterScore) { score, pattern in
                score + (text.contains(pattern) ? pattern.count : 0)
            }
        }

        var best = current
        var bestScore = score(current)
        for candidate in candidates where !LayoutPair.namesMatch(candidate, best) {
            let candidateScore = score(candidate)
            if candidateScore > bestScore {
                best = candidate
                bestScore = candidateScore
            }
        }
        return best
    }
}
