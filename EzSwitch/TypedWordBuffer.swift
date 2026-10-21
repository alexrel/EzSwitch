import Foundation

/// Only text observed since the last cursor move or focus change can be erased safely.
struct TypedWordBuffer {
    private(set) var currentWord = ""
    private(set) var text = ""

    mutating func reset() {
        currentWord = ""
        text = ""
    }

    mutating func backspace() {
        let remaining = String(text.dropLast())
        replace(with: remaining)
    }

    mutating func append(_ scalar: Unicode.Scalar) {
        if scalar == " " {
            currentWord = ""
            if !text.isEmpty { text.append(" ") }
        } else if CharacterSet.whitespacesAndNewlines.contains(scalar) || CharacterSet.controlCharacters.contains(scalar) {
            reset()
        } else {
            if text.last == " " { reset() }
            // Punctuation can be a letter in the intended layout (e.g. "[" → "х").
            text.unicodeScalars.append(scalar)
            if Self.isSeparator(scalar) { currentWord = "" }
            else { currentWord.unicodeScalars.append(scalar) }
        }
    }

    mutating func replace(with text: String) {
        reset()
        for scalar in text.unicodeScalars { append(scalar) }
    }

    static func isSeparator(_ scalar: Unicode.Scalar) -> Bool {
        " \n\t\r.,;:!?\"'()[]{}<>/\\|-_=+".unicodeScalars.contains(scalar)
    }
}

enum TerminalInput {
    static func replaysSeparator(_ separator: String) -> Bool {
        separator == "\r" || separator == "\n" || separator == "\t"
    }

    /// Pasting a mapping must never introduce terminal control sequences or submit a command.
    static func isSafeReplacement(_ text: String) -> Bool {
        !text.isEmpty && !text.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
        }
    }
}
