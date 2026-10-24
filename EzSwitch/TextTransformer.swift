import Cocoa
import Carbon
import ApplicationServices
import OSLog

final class TextTransformer {
    static let shared = TextTransformer()

    // MARK: - Timings (tuned for reliability)

    private let copyTimeoutMs: Int = Int(Constants.Timing.captureTimeoutSec * 1000)
    private let keyDownUpDelayUs: useconds_t = Constants.Timing.keyDownUpDelayUs
    private let keySequenceDelayUs: useconds_t = Constants.Timing.keySequenceDelayUs
    private let pasteSettleUs: useconds_t = Constants.Timing.pasteSettleUs
    private let restoreDelay: TimeInterval = Constants.Timing.clipboardRestoreDelay

    // MARK: - Public API

    /// Serial queue for the Cmd+C round-trip and paste sequence. These block
    /// for tens-to-hundreds of milliseconds (`usleep` between keystrokes,
    /// polling for the clipboard) and must never run on the main thread:
    /// the event tap lives on the main run loop, so blocking main delays
    /// delivery of every real keystroke the user types meanwhile.
    private let workQueue = CGEventSynthesizer.workQueue
    private var accessibilitySelection: AccessibilityTextSelection?

    /// Main entry point: tries Branch A (selection), falls back to Branch B (last word)
    ///
    /// Called on the event-tap thread (main). Layout tracking
    /// (`KeyboardManager.currentLayoutID` / `previousLayoutID`) is main-confined
    /// state, so it is snapshotted here and passed down — the Cmd+C round-trip
    /// that follows does not change the layout anyway.
    /// - Parameter skipLayoutSwitch: if true, do not switch layout after transformation
    func transformSelectedText(skipLayoutSwitch: Bool = false) {
        dispatchPrecondition(condition: .onQueue(.main))
        Log.transform.debug("Transform requested (skipLayout=\(skipLayoutSwitch ? "yes" : "no", privacy: .public))")

        let km = KeyboardManager.shared
        let currentLayout = km.currentInputSourceID() ?? km.currentLayoutID
        let previousLayout = km.previousLayoutID
        let settings = SettingsManager.shared
        let snapshot = TransformSnapshot(
            presets: MapperStore.shared.snapshot(), selectedPresetIDs: settings.selectedPresetIds,
            primaryLanguages: [settings.leftCommandLayout, settings.rightCommandLayout],
            switchLayoutAfterTransform: settings.switchLayoutAfterTransform
        )

        workQueue.async { [weak self] in
            self?.runTransform(currentLayout: currentLayout,
                               previousLayout: previousLayout,
                               snapshot: snapshot,
                               skipLayoutSwitch: skipLayoutSwitch)
        }
    }

    /// Terminal input is already known; reuse the same rules and cycling without Cmd+C.
    func planTypedText(_ text: String, completion: @escaping (TransformPlan) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        let km = KeyboardManager.shared
        let current = km.currentInputSourceID() ?? km.currentLayoutID
        let previous = km.previousLayoutID
        let settings = SettingsManager.shared
        let snapshot = TransformSnapshot(
            presets: MapperStore.shared.snapshot(), selectedPresetIDs: settings.selectedPresetIds,
            primaryLanguages: [settings.leftCommandLayout, settings.rightCommandLayout],
            switchLayoutAfterTransform: settings.switchLayoutAfterTransform
        )
        workQueue.async {
            let plan = self.planTransform(for: text, currentLayout: current, previousLayout: previous, snapshot: snapshot)
            DispatchQueue.main.async { completion(plan) }
        }
    }

    /// Runs the actual transform flow on `workQueue`.
    private func runTransform(currentLayout: String, previousLayout: String,
                              snapshot: TransformSnapshot, skipLayoutSwitch: Bool) {
        defer { accessibilitySelection = nil }
        // Save full clipboard state (including images, files, etc.)
        let clipboard = ClipboardManager.shared
        let savedState = clipboard.saveState()

        // Branch A: Try to detect and transform selected text
        if let selectedText = tryGetSelectedText() {
            completeBranchA(selectedText: selectedText, savedState: savedState,
                            currentLayout: currentLayout, previousLayout: previousLayout,
                            snapshot: snapshot,
                            skipLayoutSwitch: skipLayoutSwitch)
            return
        }

        // Branch B: Transform last word before cursor (no selection)
        Log.transform.debug("No selection — falling back to Branch B (last word)")
        tryBranchB_LastWord(savedState: savedState,
                            currentLayout: currentLayout, previousLayout: previousLayout,
                            snapshot: snapshot,
                            skipLayoutSwitch: skipLayoutSwitch)
    }

    // MARK: - Branch A: Selected Text Transformation

    /// Copies the current selection through the pasteboard: writes a marker,
    /// sends Cmd+C, then polls until the clipboard holds something other than
    /// the marker. Callers rely on the selection still being active afterwards.
    ///
    /// Modal fields without Copy/Paste shortcuts fall back to Accessibility.
    private func copySelection(timeoutMs: Int) -> String? {
        accessibilitySelection = nil
        let clipboard = ClipboardManager.shared
        let (marker, markerCount) = clipboard.setMarker()

        simulateCmdKey(keyCode: UInt16(Constants.KeyCode.c)) // Cmd+C
        usleep(keySequenceDelayUs)

        if let copied = clipboard.waitForChange(marker: marker, markerCount: markerCount, timeoutMs: timeoutMs) {
            return copied
        }
        accessibilitySelection = AccessibilityTextSelection.focused()
        return accessibilitySelection?.text
    }

    /// Reads selected text through Copy or Accessibility.
    private func tryGetSelectedText() -> String? {
        guard let copied = copySelection(timeoutMs: copyTimeoutMs) else {
            Log.transform.debug("Branch A: nothing copied — no selection")
            return nil
        }

        Log.transform.debug("Branch A selected: \"\(String(copied.prefix(50)), privacy: .public)\"")
        return copied
    }

    private func completeBranchA(selectedText: String, savedState: ClipboardManager.ClipboardState,
                                 currentLayout: String, previousLayout: String,
                                 snapshot: TransformSnapshot,
                                 skipLayoutSwitch: Bool = false) {
        // Plan multi-language transformation & cycling
        let plan = planTransform(for: selectedText, currentLayout: currentLayout, previousLayout: previousLayout, snapshot: snapshot)
        let transformed = plan.transformedText
        Log.transform.debug("Branch A: \"\(String(selectedText.prefix(30)), privacy: .public)\" → \"\(String(transformed.prefix(30)), privacy: .public)\"")

        guard pasteReplacement(transformed, savedState: savedState) else { return }

        // Switch layout if enabled (based on plan.targetLayout)
        // Skip if modifier key was held during double-tap
        if !skipLayoutSwitch && snapshot.switchLayoutAfterTransform {
            if let target = plan.targetLayout {
                Log.transform.debug("Branch A: switching layout to \(target, privacy: .public)")
                // `currentLayoutID`/`previousLayoutID` are main-confined.
                DispatchQueue.main.async { KeyboardManager.shared.switchToLayout(id: target) }
            }
        } else if skipLayoutSwitch {
            Log.transform.debug("Branch A: layout switch skipped (modifier held)")
        }
    }

    // MARK: - Branch B: Last Word Transform

    /// Transform last word before cursor (up to first space or start of line)
    /// Examples:
    /// - "hello еуые  |" → "hello test  " (preserves trailing spaces)
    /// - "hello еуые |" → "hello test "
    /// - "еуые |" → "test "
    /// - "еуые|" → "test"
    private func tryBranchB_LastWord(savedState: ClipboardManager.ClipboardState,
                                     currentLayout: String, previousLayout: String,
                                     snapshot: TransformSnapshot,
                                     skipLayoutSwitch: Bool = false) {
        // Try to select word using smart method (tries both macOS and IDE shortcuts)
        guard let (rawSelection, _) = trySelectWordBackward() else {
            Log.transform.debug("Branch B: could not select a word")
            ClipboardManager.shared.restoreState(savedState)
            return
        }

        // Parse selection - extract word and trailing spaces
        let parsed = parseWordSelection(rawSelection)

        guard !parsed.word.isEmpty else {
            Log.transform.debug("Branch B: selection \"\(rawSelection, privacy: .public)\" has no word to transform")
            sendKeyPress(keyCode: UInt16(Constants.KeyCode.rightArrow)) // Deselect
            ClipboardManager.shared.restoreState(savedState)
            return
        }

        Log.transform.debug("Branch B word: \"\(parsed.word, privacy: .public)\" (trailing=\(parsed.trailingSpaces.count, privacy: .public), leading=\(parsed.leadingSpaces.count, privacy: .public))")

        // If there were leading spaces, shrink selection to exclude them
        if accessibilitySelection == nil && !parsed.leadingSpaces.isEmpty {
            for _ in parsed.leadingSpaces {
                sendShiftRight()
                usleep(Constants.Timing.betweenCharsDelayUs)
            }
            usleep(keySequenceDelayUs)
        }

        // Transform and paste (supporting multi-language cycle)
        let plan = planTransform(for: parsed.word, currentLayout: currentLayout, previousLayout: previousLayout, snapshot: snapshot)
        let transformedWord = plan.transformedText
        let replacement = (accessibilitySelection == nil ? "" : parsed.leadingSpaces) + transformedWord + parsed.trailingSpaces
        Log.transform.debug("Branch B: \"\(parsed.word, privacy: .public)\" → \"\(transformedWord, privacy: .public)\"")

        guard pasteReplacement(replacement, savedState: savedState) else { return }

        // Switch layout if enabled (based on plan.targetLayout)
        // Skip if modifier key was held during double-tap
        if !skipLayoutSwitch && snapshot.switchLayoutAfterTransform {
            if let target = plan.targetLayout {
                Log.transform.debug("Branch B: switching layout to \(target, privacy: .public)")
                DispatchQueue.main.async { KeyboardManager.shared.switchToLayout(id: target) }
            }
        } else if skipLayoutSwitch {
            Log.transform.debug("Branch B: layout switch skipped (modifier held)")
        }
    }

    private func pasteReplacement(_ text: String, savedState: ClipboardManager.ClipboardState) -> Bool {
        let clipboard = ClipboardManager.shared
        if let selection = accessibilitySelection {
            let replaced = selection.replace(with: text)
            clipboard.restoreState(savedState)
            if !replaced {
                activeCycle = nil
                Log.transform.debug("Accessibility replacement failed or selection changed")
            }
            return replaced
        }
        clipboard.setString(text)
        let pasteCount = NSPasteboard.general.changeCount
        usleep(keySequenceDelayUs)
        simulateCmdKey(keyCode: UInt16(Constants.KeyCode.v))
        usleep(pasteSettleUs)
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            clipboard.restoreState(savedState, ifUnchangedSince: pasteCount)
        }
        return true
    }

    /// Tries to select word backward using app-specific method from AppConfigRegistry
    /// Returns: (selection text, method used) or nil if failed
    private func trySelectWordBackward() -> (String, String)? {
        let bundleId = AppConfigRegistry.frontmostAppBundleId()
        let method = AppConfigRegistry.shared.wordSelectionMethod(for: bundleId)

        if let config = AppConfigRegistry.shared.config(for: bundleId) {
            Log.transform.debug("Frontmost app \(config.displayName, privacy: .public) (\(bundleId ?? "unknown", privacy: .public)) → selection method \(method.description, privacy: .public)")
        } else {
            Log.transform.debug("Frontmost app \(bundleId ?? "unknown", privacy: .public) has no config → default selection method \(method.description, privacy: .public)")
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
            Log.transform.debug("Option+Shift+Left failed — falling back to Ctrl+Shift+Left")
            return trySelectWithCtrlShift()
        }
    }

    /// Selects word using Option+Shift+Left (macOS standard)
    /// Handles cases like "cfvb[" where [ is treated as word boundary
    private func trySelectWithOptionShift() -> (String, String)? {
        var fullSelection = ""
        let maxIterations = Constants.WordSelection.maxIterations // Safety limit

        for iteration in 0..<maxIterations {
            sendOptionShiftLeft()
            usleep(keySequenceDelayUs)

            guard let selection = copyCurrentSelection() else {
                if fullSelection.isEmpty {
                    Log.transform.debug("Option+Shift+Left: no selection on first press")
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
            Log.transform.debug("Extending selection, iteration \(iteration + 1, privacy: .public): \"\(selection, privacy: .public)\"")
        }

        if isValidWordSelection(fullSelection) {
            Log.transform.debug("Option+Shift+Left selected: \"\(fullSelection, privacy: .public)\"")
            return (fullSelection, "option")
        } else {
            Log.transform.debug("Option+Shift+Left produced an invalid selection (\"\(fullSelection, privacy: .public)\") — not a single word")
            sendKeyPress(keyCode: UInt16(Constants.KeyCode.rightArrow))
            usleep(keySequenceDelayUs)
            return nil
        }
    }

    /// Selects word using Ctrl+Shift+Left (IDE standard)
    private func trySelectWithCtrlShift() -> (String, String)? {
        sendCtrlShiftLeft()
        usleep(keySequenceDelayUs)

        if let selection = copyCurrentSelection(), isValidWordSelection(selection) {
            Log.transform.debug("Ctrl+Shift+Left selected: \"\(selection, privacy: .public)\"")
            return (selection, "ctrl")
        } else {
            Log.transform.debug("Ctrl+Shift+Left produced no usable selection")
            sendKeyPress(keyCode: UInt16(Constants.KeyCode.rightArrow)) // Deselect
            usleep(keySequenceDelayUs)
            return nil
        }
    }

    /// Copies current selection and returns it
    private func copyCurrentSelection() -> String? {
        copySelection(timeoutMs: Int(Constants.Timing.captureSelectionTimeoutSec * 1000))
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
        let snapshot: TransformSnapshot
        let originalText: String
        let originalLayout: String
        let steps: [(targetLayout: String, text: String)]
        var currentStepIndex: Int
        var timestamp: Date
    }

    private var activeCycle: TransformCycle?

    /// Characters a layout can produce with the base and Shift modifiers,
    /// cached per layout value. Used to decide which of the configured layouts
    /// the text was actually typed in — independent of layout naming.
    private var layoutCharacterCache: [String: Set<Character>] = [:]

    private func charactersProduced(by layout: String) -> Set<Character> {
        if let cached = layoutCharacterCache[layout] { return cached }
        let entries = KeyboardLayoutUtility.characterTable(forLayout: layout)
            .filter { $0.modifier == .none || $0.modifier == .shift }
        let set = Set(entries.map { $0.character })
        layoutCharacterCache[layout] = set
        return set
    }

    /// Pick the layout the text is most plausibly written in. The current
    /// layout wins ties. Extra-rule sources and targets are evidence even
    /// when they are Option symbols or punctuation absent from the base map.
    private func detectSourceLayout(for text: String, current: String, candidates: [String],
                                    snapshot: TransformSnapshot) -> String {
        TransformSourceDetection.layout(
            for: text, current: current, candidates: candidates,
            activePresets: snapshot.activePresets, charactersProduced: charactersProduced(by:)
        )
    }

    private func layoutsMatch(_ a: String, _ b: String) -> Bool {
        LayoutPair.namesMatch(a, b)
    }

    /// Plans and returns the text transformation and target layout for a given input word/selection,
    /// supporting multi-language cycling and prioritizing previousLayout.
    /// - Parameters: `currentLayout`/`previousLayout` are snapshots taken on
    ///   the main thread by the caller (this runs on `workQueue`).
    private func planTransform(for rawText: String, currentLayout: String, previousLayout: String,
                               snapshot: TransformSnapshot) -> TransformPlan {
        let now = Date()

        // 1. Check for consecutive Double Shift (Cycle advancement)
        if let cycle = activeCycle,
           cycle.snapshot == snapshot,
           now.timeIntervalSince(cycle.timestamp) < Constants.Timing.cycleExpirySec,
           (rawText == cycle.steps[cycle.currentStepIndex].text || rawText == cycle.originalText) {

            let nextIndex = cycle.currentStepIndex + 1
            if nextIndex < cycle.steps.count {
                activeCycle?.currentStepIndex = nextIndex
                activeCycle?.timestamp = now
                let step = cycle.steps[nextIndex]
                Log.transform.debug("Cycle advancing to step \(nextIndex + 1, privacy: .public)/\(cycle.steps.count, privacy: .public) → \(step.targetLayout, privacy: .public)")
                return TransformPlan(transformedText: step.text, targetLayout: step.targetLayout)
            } else {
                // Reached end of cycle -> Undo back to original input!
                Log.transform.debug("Cycle finished — undoing back to \(cycle.originalLayout, privacy: .public)")
                activeCycle = nil
                return TransformPlan(transformedText: cycle.originalText, targetLayout: cycle.originalLayout)
            }
        }

        // 2. Fresh transformation
        // Layout snapshots arrive from the caller (main thread) — do not
        // touch KeyboardManager's main-confined state from this queue.
        activeCycle = nil
        let primaryLanguages = snapshot.primaryLanguages

        // Source layout: whatever layout can actually type the text, not the
        // layout name. The current input source wins ties.
        let sourceLayout = detectSourceLayout(
            for: rawText,
            current: currentLayout,
            candidates: primaryLanguages + snapshot.activePresets.flatMap { [$0.fromLayout, $0.toLayout] },
            snapshot: snapshot
        )
        Log.transform.debug("Plan for \"\(rawText, privacy: .public)\": detected source \(sourceLayout, privacy: .public) (current \(currentLayout, privacy: .public), previous \(previousLayout, privacy: .public))")

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
            if let transformed = snapshot.transform(text: rawText, from: sourceLayout, to: candidate),
               transformed != rawText {
                steps.append((targetLayout: candidate, text: transformed))
            }
        }

        // If no preset can transform the text (missing mapping, unknown layout),
        // return it unchanged and leave the active layout alone.
        // Not an error: a third language with no preset is a normal state, and
        // the transform legitimately does nothing there. Logged at .debug so a
        // "double tap did nothing" report can be answered without a debugger.
        if steps.isEmpty {
            let targets = targetCandidates.joined(separator: ", ")
            Log.transform.debug("Transform skipped: no preset maps \(sourceLayout, privacy: .public) → \(targets, privacy: .public)")
            return TransformPlan(transformedText: rawText, targetLayout: nil)
        }

        // Save active cycle state
        activeCycle = TransformCycle(
            snapshot: snapshot,
            originalText: rawText,
            originalLayout: sourceLayout,
            steps: steps,
            currentStepIndex: 0,
            timestamp: now
        )

        let firstStep = steps[0]
        Log.transform.debug("New cycle with \(steps.count, privacy: .public) step(s), first target \(firstStep.targetLayout, privacy: .public)")
        return TransformPlan(transformedText: firstStep.text, targetLayout: firstStep.targetLayout)
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
}
