import Foundation

/// Result of a successful word-level substitution lookup.
struct WordMatchResult {
    /// The exact word the user typed (verbatim, including case).
    let original: String
    /// The replacement string, with case restored to match `original`.
    let replacement: String
    /// The target layout to switch to, if layout switching is enabled for this match.
    var targetLayout: String? = nil
}

/// Two-stage matcher for word-level substitutions.
///
/// Stage 1 — exact match: look up the typed word verbatim.
/// Stage 2 — lowercase fallback: lowercase the typed word, look it up, then
///           restore the original case onto the matched replacement.
///
/// The case-restore step copies the case pattern from the typed word onto
/// the stored lowercase replacement so things like `ОЫЩТ → JSON` work
/// even if only `оыщт → json` was ever saved.
enum WordMatcher {

    /// Find a substitution for `word` in `entries`. Returns `nil` if neither
    /// an exact nor a lowercase match exists.
    static func findMatch(word: String, in entries: [String: String]) -> WordMatchResult? {
        if let direct = entries[word] {
            return WordMatchResult(original: word, replacement: direct)
        }
        let lower = word.lowercased()
        if lower == word {
            // Already lowercase — exact lookup would have caught it.
            return nil
        }
        if let lowerTarget = entries[lower] {
            let restored = restoreCase(from: word, to: lowerTarget)
            return WordMatchResult(original: word, replacement: restored)
        }
        return nil
    }

    /// Copy the case pattern from `original` onto `target`.
    ///
    /// Rules:
    /// - If every letter in `original` is uppercase → uppercase `target`.
    /// - Else if `original` is "capitalized" (first letter upper, rest lower)
    ///   → uppercase only the first letter of `target`.
    /// - Else → per-character case copy, padding the shorter string with
    ///   spaces (so `"git"` typed as `"GiT"` doesn't bleed into the buffer).
    static func restoreCase(from original: String, to target: String) -> String {
        let letters = original.filter { $0.isLetter }
        guard !letters.isEmpty else { return target }

        if letters == letters.uppercased() {
            return target.uppercased()
        }
        if let first = letters.first, first.isUppercase,
           letters.dropFirst().lowercased() == letters.dropFirst() {
            return target.prefix(1).uppercased() + target.dropFirst().lowercased()
        }
        return perCharacterRestore(from: original, to: target)
    }

    private static func perCharacterRestore(from original: String, to target: String) -> String {
        let orig = Array(original)
        let targ = Array(target)
        let n = max(orig.count, targ.count)
        var result = ""
        for i in 0..<n {
            let src = i < orig.count ? orig[i] : Character(" ")
            let tgt = i < targ.count ? targ[i] : Character(" ")
            if src.isUppercase {
                result.append(Character(String(tgt).uppercased()))
            } else if src.isLowercase {
                result.append(Character(String(tgt).lowercased()))
            } else {
                result.append(tgt)
            }
        }
        return result
    }
}
