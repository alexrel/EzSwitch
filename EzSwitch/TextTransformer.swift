import Cocoa
import Carbon
import ApplicationServices

final class TextTransformer {
    static let shared = TextTransformer()

    // MARK: - Timings (tuned for reliability)

    private let copyTimeoutMs: Int = Int(Constants.Timing.captureTimeoutSec * 1000)
    private let keyDownUpDelayUs: useconds_t = Constants.Timing.keyDownUpDelayUs
    private let keySequenceDelayUs: useconds_t = Constants.Timing.keySequenceDelayUs
    private let pasteSettleUs: useconds_t = Constants.Timing.pasteSettleUs
    private let restoreDelay: TimeInterval = Constants.Timing.clipboardRestoreDelay

    // MARK: - Public API

    /// Main entry point: tries Branch A (selection), falls back to Branch B (last word)
    /// - Parameter skipLayoutSwitch: if true, do not switch layout after transformation
    func transformSelectedText(skipLayoutSwitch: Bool = false) {
        print("\n🔄 [TextTransformer] ═══════════════════════════════════")
        print("🔄 [TextTransformer] Transform requested (skipLayout: \(skipLayoutSwitch))")

        // Save full clipboard state (including images, files, etc.)
        let clipboard = ClipboardManager.shared
        let savedState = clipboard.saveState()

        // Branch A: Try to detect and transform selected text
        if let selectedText = tryGetSelectedText() {
            print("✅ [TextTransformer] Branch A: selection detected")
            completeBranchA(selectedText: selectedText, savedState: savedState, skipLayoutSwitch: skipLayoutSwitch)
            return
        }

        // Branch B: Transform last word before cursor (no selection)
        print("🔀 [TextTransformer] Branch A: no selection, trying Branch B (last word)")
        tryBranchB_LastWord(savedState: savedState, skipLayoutSwitch: skipLayoutSwitch)
    }

    // MARK: - Branch A: Selected Text Transformation

    /// Attempts to copy selected text using Cmd+C
    private func tryGetSelectedText() -> String? {
        print("📋 [Branch A] Attempting to copy selection")

        let clipboard = ClipboardManager.shared
        let (marker, markerCount) = clipboard.setMarker()

        // Send Cmd+C with proper timing
        simulateCmdKey(keyCode: UInt16(Constants.KeyCode.c)) // C
        usleep(keySequenceDelayUs)

        // Wait for clipboard to change
        guard let copied = clipboard.waitForChange(marker: marker, markerCount: markerCount, timeoutMs: copyTimeoutMs) else {
            print("📋 [Branch A] Copy failed or no selection")
            return nil
        }

        print("📋 [Branch A] Got selection: \"\(copied.prefix(50))\"")
        return copied
    }

    private func completeBranchA(selectedText: String, savedState: ClipboardManager.ClipboardState, skipLayoutSwitch: Bool = false) {
        // Plan multi-language transformation & cycling
        let plan = planTransform(for: selectedText)
        let transformed = plan.transformedText
        print("🔄 [Branch A] Transform: \"\(selectedText.prefix(30))\" → \"\(transformed.prefix(30))\"")

        // Put transformed text to clipboard and paste (single Undo action)
        ClipboardManager.shared.setString(transformed)
        usleep(keySequenceDelayUs)

        // Paste replaces selection automatically
        print("⌨️  [Branch A] Pasting transformed text")
        simulateCmdKey(keyCode: UInt16(Constants.KeyCode.v)) // Cmd+V
        usleep(pasteSettleUs)

        // Switch layout if enabled (based on plan.targetLayout)
        // Skip if modifier key was held during double-tap
        if !skipLayoutSwitch && SettingsManager.shared.switchLayoutAfterTransform {
            if let target = plan.targetLayout {
                print("⌨️  [Branch A] Switching layout to: \(target)")
                KeyboardManager.shared.switchToLayout(named: target)
            }
        } else if skipLayoutSwitch {
            print("⌨️  [Branch A] Layout switch skipped (modifier held)")
        }

        // Restore clipboard (full state including images, files, etc.)
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            ClipboardManager.shared.restoreState(savedState)
            print("📋 [Branch A] Clipboard restored")
        }

        print("✅ [Branch A] Complete")
    }

    // MARK: - Branch B: Last Word Transform

    /// Transform last word before cursor (up to first space or start of line)
    /// Examples:
    /// - "hello еуые  |" → "hello test  " (preserves trailing spaces)
    /// - "hello еуые |" → "hello test "
    /// - "еуые |" → "test "
    /// - "еуые|" → "test"
    private func tryBranchB_LastWord(savedState: ClipboardManager.ClipboardState, skipLayoutSwitch: Bool = false) {
        print("🎯 [Branch B] Starting last-word transform")

        // Try to select word using smart method (tries both macOS and IDE shortcuts)
        guard let (rawSelection, _) = trySelectWordBackward() else {
            print("ℹ️  [Branch B] Could not select word")
            ClipboardManager.shared.restoreState(savedState)
            return
        }

        print("📝 [Branch B] Raw selection: \"\(rawSelection)\"")

        // Parse selection - extract word and trailing spaces
        let parsed = parseWordSelection(rawSelection)

        guard !parsed.word.isEmpty else {
            print("ℹ️  [Branch B] No word in selection")
            sendKeyPress(keyCode: UInt16(Constants.KeyCode.rightArrow)) // Deselect
            ClipboardManager.shared.restoreState(savedState)
            return
        }

        print("📝 [Branch B] Word: \"\(parsed.word)\", trailing: \(parsed.trailingSpaces.count), leading: \(parsed.leadingSpaces.count)")

        // If there were leading spaces, shrink selection to exclude them
        if !parsed.leadingSpaces.isEmpty {
            print("⌨️  [Branch B] Shrinking selection to exclude \(parsed.leadingSpaces.count) leading spaces")
            for _ in parsed.leadingSpaces {
                sendShiftRight()
                usleep(Constants.Timing.betweenCharsDelayUs)
            }
            usleep(keySequenceDelayUs)
        }

        // Transform and paste (supporting multi-language cycle)
        let plan = planTransform(for: parsed.word)
        let transformedWord = plan.transformedText
        let replacement = transformedWord + parsed.trailingSpaces
        print("🔄 [Branch B] Transform: \"\(parsed.word)\" → \"\(transformedWord)\"")

        // Put to clipboard and paste (single Undo)
        ClipboardManager.shared.setString(replacement)
        usleep(keySequenceDelayUs)

        print("⌨️  [Branch B] Pasting replacement")
        simulateCmdKey(keyCode: UInt16(Constants.KeyCode.v)) // Cmd+V
        usleep(pasteSettleUs)

        // Switch layout if enabled (based on plan.targetLayout)
        // Skip if modifier key was held during double-tap
        if !skipLayoutSwitch && SettingsManager.shared.switchLayoutAfterTransform {
            if let target = plan.targetLayout {
                print("⌨️  [Branch B] Switching layout to: \(target)")
                KeyboardManager.shared.switchToLayout(named: target)
            }
        } else if skipLayoutSwitch {
            print("⌨️  [Branch B] Layout switch skipped (modifier held)")
        }

        // Restore clipboard (full state including images, files, etc.)
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            ClipboardManager.shared.restoreState(savedState)
            print("📋 [Branch B] Clipboard restored")
        }

        print("✅ [Branch B] Complete")
    }

    /// Tries to select word backward using app-specific method from AppConfigRegistry
    /// Returns: (selection text, method used) or nil if failed
    private func trySelectWordBackward() -> (String, String)? {
        let bundleId = AppConfigRegistry.frontmostAppBundleId()
        let method = AppConfigRegistry.shared.wordSelectionMethod(for: bundleId)

        if let config = AppConfigRegistry.shared.config(for: bundleId) {
            print("📱 [Branch B] App: \(config.displayName) (\(bundleId ?? "unknown")), method: \(method)")
        } else {
            print("📱 [Branch B] Unknown app: \(bundleId ?? "nil"), using default: \(method)")
        }

        switch method {
        case .optionShiftLeft:
            return trySelectWithOptionShift()

        case .ctrlShiftLeft:
            return trySelectWithCtrlShift()

        case .auto:
            // Try Option first, fallback to Ctrl
            if let result = trySelectWithOptionShift() {
                return result
            }
            print("⚠️  [Branch B] Option+Shift+Left failed, trying Ctrl+Shift+Left")
            return trySelectWithCtrlShift()
        }
    }

    /// Selects word using Option+Shift+Left (macOS standard)
    /// Handles cases like "cfvb[" where [ is treated as word boundary
    private func trySelectWithOptionShift() -> (String, String)? {
        print("⌨️  [Branch B] Using Option+Shift+Left (macOS)")

        var fullSelection = ""
        let maxIterations = Constants.WordSelection.maxIterations // Safety limit

        for iteration in 0..<maxIterations {
            sendOptionShiftLeft()
            usleep(keySequenceDelayUs)

            guard let selection = copyCurrentSelection() else {
                if fullSelection.isEmpty {
                    print("⚠️  [Branch B] Option+Shift+Left failed - no selection")
                    sendKeyPress(keyCode: UInt16(Constants.KeyCode.rightArrow))
                    usleep(keySequenceDelayUs)
                    return nil
                }
                break
            }

            // Check if selection grew or this is first iteration
            if iteration == 0 {
                fullSelection = selection
            } else if selection.count > fullSelection.count {
                fullSelection = selection
            } else {
                // Selection didn't grow, we're done
                break
            }

            // If selection ends with space or newline, we have the full word
            if selection.first == " " || selection.first == "\n" || selection.first == "\t" {
                break
            }

            // If we got a reasonable word (has letters), check if we should continue
            let trimmed = selection.trimmingCharacters(in: .whitespaces)
            if trimmed.count > 1 && (trimmed.first?.isLetter == true || trimmed.first?.isNumber == true) {
                // Got a word starting with letter/number, probably done
                break
            }

            // Selection is just punctuation/symbols, continue selecting
            print("⌨️  [Branch B] Extending selection (iteration \(iteration + 1)): \"\(selection)\"")
        }

        if isValidWordSelection(fullSelection) {
            print("✅ [Branch B] Option+Shift+Left worked: \"\(fullSelection)\"")
            return (fullSelection, "option")
        } else {
            print("⚠️  [Branch B] Option+Shift+Left failed - invalid selection")
            sendKeyPress(keyCode: UInt16(Constants.KeyCode.rightArrow))
            usleep(keySequenceDelayUs)
            return nil
        }
    }

    /// Selects word using Ctrl+Shift+Left (IDE standard)
    private func trySelectWithCtrlShift() -> (String, String)? {
        print("⌨️  [Branch B] Using Ctrl+Shift+Left (IDE)")
        sendCtrlShiftLeft()
        usleep(keySequenceDelayUs)

        if let selection = copyCurrentSelection(), isValidWordSelection(selection) {
            print("✅ [Branch B] Ctrl+Shift+Left worked")
            return (selection, "ctrl")
        } else {
            print("⚠️  [Branch B] Ctrl+Shift+Left failed")
            sendKeyPress(keyCode: UInt16(Constants.KeyCode.rightArrow)) // Deselect
            usleep(keySequenceDelayUs)
            return nil
        }
    }

    /// Copies current selection and returns it
    private func copyCurrentSelection() -> String? {
        let clipboard = ClipboardManager.shared
        let (marker, markerCount) = clipboard.setMarker()

        simulateCmdKey(keyCode: UInt16(Constants.KeyCode.c)) // Cmd+C
        usleep(keySequenceDelayUs)

        return clipboard.waitForChange(marker: marker, markerCount: markerCount, timeoutMs: Int(Constants.Timing.captureSelectionTimeoutSec * 1000))
    }

    /// Checks if selection looks like a valid word (not whole line, no newlines)
    private func isValidWordSelection(_ text: String) -> Bool {
        // Invalid if contains newline
        if text.contains("\n") || text.contains("\r") {
            return false
        }
        // Invalid if too long (probably selected whole line)
        if text.count > Constants.WordSelection.maxWordLength {
            return false
        }
        // Invalid if empty
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        return true
    }

    /// Parses word selection to extract: leading spaces, word, trailing spaces
    private func parseWordSelection(_ text: String) -> (leadingSpaces: String, word: String, trailingSpaces: String) {
        var leading = ""
        var word = ""
        var trailing = ""

        var state = 0 // 0 = collecting leading, 1 = collecting word, 2 = collecting trailing

        for char in text {
            switch state {
            case 0:
                if char == " " || char == "\t" {
                    leading.append(char)
                } else {
                    word.append(char)
                    state = 1
                }
            case 1:
                if char == " " || char == "\t" {
                    trailing.append(char)
                    state = 2
                } else {
                    word.append(char)
                }
            case 2:
                trailing.append(char)
            default:
                break
            }
        }

        return (leading, word, trailing)
    }

    /// Sends Ctrl+Shift+Left Arrow (select word backward - works in IDEs)
    private func sendCtrlShiftLeft() {
        CGEventSynthesizer.press(
            Constants.KeyCode.leftArrow,
            flags: [.maskShift, .maskControl]
        )
    }

    /// Sends Option+Shift+Left Arrow (select word backward - macOS standard)
    private func sendOptionShiftLeft() {
        CGEventSynthesizer.press(
            Constants.KeyCode.leftArrow,
            flags: [.maskShift, .maskAlternate]
        )
    }

    /// Sends Shift+Right Arrow (shrink selection by one character)
    private func sendShiftRight() {
        CGEventSynthesizer.press(
            Constants.KeyCode.rightArrow,
            flags: .maskShift
        )
    }

    // MARK: - Experimental Multi-Language Pivot & Cycle
    // Added as an experimental feature: allows seamless cycling across multiple
    // languages (e.g. Hebrew -> Russian -> English -> Undo) using 'previousLayout'
    // and presets connecting to the primary switcher pair.

    struct TransformPlan {
        let transformedText: String
        let targetLayout: String?
    }

    private struct TransformCycle {
        let originalText: String
        let originalLayout: String
        let steps: [(targetLayout: String, text: String)]
        var currentStepIndex: Int
        var timestamp: Date
    }

    private var activeCycle: TransformCycle?

    /// Characters a layout can produce with the base and Shift modifiers,
    /// cached per layout name. Used to decide which of the configured layouts
    /// the text was actually typed in — independent of layout naming.
    private var layoutCharacterCache: [String: Set<Character>] = [:]

    private func charactersProduced(by layout: String) -> Set<Character> {
        if let cached = layoutCharacterCache[layout] { return cached }
        let entries = KeyboardLayoutUtility.characterTable(forLayoutNamed: layout)
            .filter { $0.modifier == .none || $0.modifier == .shift }
        let set = Set(entries.map { $0.character })
        layoutCharacterCache[layout] = set
        return set
    }

    /// How many letters of `text` this layout can type. Only letters are
    /// scored: digits, punctuation and symbols are shared by most layouts, so
    /// they would make every candidate look equally plausible.
    private func layoutMatchScore(_ text: String, layout: String) -> Int {
        guard !layout.isEmpty, layout != Constants.Default.noneLanguage else { return 0 }
        let characters = charactersProduced(by: layout)
        return text.reduce(0) { score, ch in
            ch.isLetter && characters.contains(ch) ? score + 1 : score
        }
    }

    /// Pick the layout the text is most plausibly written in. The current
    /// layout wins ties, so text made only of shared characters keeps its
    /// existing behaviour.
    private func detectSourceLayout(for text: String, current: String, candidates: [String]) -> String {
        var best = current
        var bestScore = layoutMatchScore(text, layout: current)

        for candidate in candidates where !layoutsMatch(candidate, current) {
            let score = layoutMatchScore(text, layout: candidate)
            if score > bestScore {
                best = candidate
                bestScore = score
            }
        }
        return best
    }

    private func layoutsMatch(_ a: String, _ b: String) -> Bool {
        LayoutPair.namesMatch(a, b)
    }

    /// Transforms `text` between any two layouts using direct presets or a bridge hop if needed.
    func transform(text: String, from fromLayout: String, to toLayout: String) -> String? {
        transform(text: text, from: fromLayout, to: toLayout, depth: 0)
    }

    /// `depth` bounds the bridge search: a direct preset needs one hop, a
    /// bridge needs two. Without a limit, presets that form a cycle
    /// (A→B, B→C, C→A) recurse forever because each hop changes the text.
    private func transform(text: String, from fromLayout: String, to toLayout: String, depth: Int) -> String? {
        guard depth < 3 else { return nil }
        if layoutsMatch(fromLayout, toLayout) { return text }
        let store = MapperStore.shared

        // 1. Try direct presets
        let directPresets = store.presets(for: LayoutPair(from: fromLayout, to: toLayout))
        if let preset = directPresets.first {
            // `applyReverse` needs the *forward* map: it inverts it itself,
            // including multi-character targets via longest-match.
            let mapping = preset.characterMapping()
            let result = layoutsMatch(preset.pair.from, fromLayout)
                ? applyForward(text, mapper: mapping)
                : applyReverse(text, forward: mapping)
            if result != text { return result }
        }

        // 2. Try bridging via an intermediate layout (e.g. Hebrew -> Russian -> English)
        for preset in store.presets {
            let pair = preset.pair
            var bridge: String? = nil
            if layoutsMatch(pair.from, fromLayout) { bridge = pair.to }
            else if layoutsMatch(pair.to, fromLayout) { bridge = pair.from }

            if let b = bridge, !layoutsMatch(b, fromLayout), !layoutsMatch(b, toLayout) {
                let secondHop = store.presets(for: LayoutPair(from: b, to: toLayout))
                if !secondHop.isEmpty {
                    if let intermediate = transform(text: text, from: fromLayout, to: b, depth: depth + 1),
                       intermediate != text,
                       let finalResult = transform(text: intermediate, from: b, to: toLayout, depth: depth + 1) {
                        return finalResult
                    }
                }
            }
        }
        return nil
    }

    /// Plans and returns the text transformation and target layout for a given input word/selection,
    /// supporting multi-language cycling and prioritizing previousLayout.
    private func planTransform(for rawText: String) -> TransformPlan {
        let now = Date()

        // 1. Check for consecutive Double Shift (Cycle advancement)
        if let cycle = activeCycle,
           now.timeIntervalSince(cycle.timestamp) < 2.5,
           (rawText == cycle.steps[cycle.currentStepIndex].text || rawText == cycle.originalText) {

            let nextIndex = cycle.currentStepIndex + 1
            if nextIndex < cycle.steps.count {
                activeCycle?.currentStepIndex = nextIndex
                activeCycle?.timestamp = now
                let step = cycle.steps[nextIndex]
                print("🔄 [Transform Cycle] Advancing to step \(nextIndex + 1)/\(cycle.steps.count): -> \(step.targetLayout)")
                return TransformPlan(transformedText: step.text, targetLayout: step.targetLayout)
            } else {
                // Reached end of cycle -> Undo back to original input!
                print("🔄 [Transform Cycle] Reached end -> Undo to original layout: \(cycle.originalLayout)")
                activeCycle = nil
                return TransformPlan(transformedText: cycle.originalText, targetLayout: cycle.originalLayout)
            }
        }

        // 2. Fresh transformation
        let km = KeyboardManager.shared
        let currentLayout = km.currentLayoutName() ?? km.currentLayoutID
        let previousLayout = km.previousLayoutID
        let settings = SettingsManager.shared
        let primaryLanguages = [settings.leftCommandLanguage, settings.rightCommandLanguage]
            .filter { $0 != Constants.Default.noneLanguage && !$0.isEmpty }

        // Source layout: whatever layout can actually type the text, not the
        // layout name. The current input source wins ties.
        let sourceLayout = detectSourceLayout(
            for: rawText,
            current: currentLayout,
            candidates: primaryLanguages + MapperStore.shared.presets.flatMap { [$0.fromLayout, $0.toLayout] }
        )
        print("🔄 [planTransform] Text: \"\(rawText)\", sourceLayout: \(sourceLayout), current: \(currentLayout), previous: \(previousLayout)")

        // Determine target candidates:
        // Candidates are ONLY chosen from the user's primary switcher pair (e.g. Russian and English).
        var targetCandidates: [String] = []

        let sourceIsPrimary = primaryLanguages.contains(where: { layoutsMatch($0, sourceLayout) })
        if sourceIsPrimary {
            // Source is one of the primary languages -> target is the other primary language
            for lang in primaryLanguages {
                if !layoutsMatch(lang, sourceLayout) {
                    targetCandidates.append(lang)
                }
            }
        } else {
            // Source is a 3rd language (e.g. Hebrew or Spanish):
            // Prioritize previousLayout if it belongs to primaryLanguages
            if !previousLayout.isEmpty,
               primaryLanguages.contains(where: { layoutsMatch($0, previousLayout) }),
               !layoutsMatch(previousLayout, sourceLayout) {
                targetCandidates.append(previousLayout)
            }
            // Append remaining primary languages
            for lang in primaryLanguages {
                if !targetCandidates.contains(where: { layoutsMatch($0, lang) }) && !layoutsMatch(lang, sourceLayout) {
                    targetCandidates.append(lang)
                }
            }
        }

        // Build cycle transformation steps
        var steps: [(targetLayout: String, text: String)] = []
        for candidate in targetCandidates {
            if let transformed = transform(text: rawText, from: sourceLayout, to: candidate),
               transformed != rawText {
                steps.append((targetLayout: candidate, text: transformed))
            }
        }

        // If no preset can transform the text (missing mapping, unknown layout),
        // return it unchanged and leave the active layout alone.
        if steps.isEmpty {
            print("⚠️ [planTransform] No preset can transform \(sourceLayout) → \(targetCandidates)")
            return TransformPlan(transformedText: rawText, targetLayout: nil)
        }

        // Save active cycle state
        activeCycle = TransformCycle(
            originalText: rawText,
            originalLayout: sourceLayout,
            steps: steps,
            currentStepIndex: 0,
            timestamp: now
        )

        let firstStep = steps[0]
        print("🔄 [planTransform] Cycle initiated with \(steps.count) step(s). First target: \(firstStep.targetLayout)")
        return TransformPlan(transformedText: firstStep.text, targetLayout: firstStep.targetLayout)
    }

    // MARK: - Direction Detection

    /// Apply a forward `[Character: String]` mapping character by character.
    private func applyForward(_ text: String, mapper: [Character: String]) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for char in text {
            if let mapped = mapper[char] {
                result.append(mapped)
            } else {
                result.append(char)
            }
        }
        return result
    }

    /// Apply the inverse of a forward `[Character: String]` mapping.
    private func applyReverse(_ text: String, forward: [Character: String]) -> String {
        var multiPatterns: [(String, String)] = []
        var charMap: [Character: String] = [:]

        for (k, v) in forward {
            if v.count == 1 {
                charMap[v.first!] = String(k)
            } else {
                multiPatterns.append((v, String(k)))
            }
        }
        let multiStarts: Set<Character> = Set(multiPatterns.map { $0.0.first! })
        for c in multiStarts {
            charMap.removeValue(forKey: c)
        }
        multiPatterns.sort { $0.0.count > $1.0.count }

        var result = ""
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
            if matched { continue }
            let char = text[i]
            if let mapped = charMap[char] {
                result.append(mapped)
            } else {
                result.append(char)
            }
            i = text.index(after: i)
        }
        return result
    }

    // MARK: - Keyboard Helpers

    /// Sends a single key press (down + up) with proper timing
    private func sendKeyPress(keyCode: CGKeyCode) {
        CGEventSynthesizer.press(keyCode)
    }

    /// Sends Cmd+Key combination with proper timing
    private func simulateCmdKey(keyCode: CGKeyCode) {
        CGEventSynthesizer.pressCommand(Int(keyCode), delayUs: keyDownUpDelayUs)
    }

    // MARK: - Layout Detection & Switching

}
