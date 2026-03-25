import Cocoa
import Carbon
import ApplicationServices

final class TextTransformer {
    static let shared = TextTransformer()

    // MARK: - Dynamic Mapper System
    
    /// Layout pair identifier
    private struct LayoutPair: Hashable {
        let from: String
        let to: String
    }
    
    /// Registry of all available mappers
    private var mappers: [LayoutPair: [Character: Character]] = [:]
    
    /// All available mapper instances
    private var mapperInstances: [LayoutMapper] = []
    
    /// Initialize mappers on first use
    private lazy var initializedMappers: Void = {
        initializeMappers()
    }()
    
    // MARK: - Mapper Initialization
    
    /// Initialize all available mappers from files
    private func initializeMappers() {
        // Register built-in mappers (only forward direction)
        mapperInstances = [
            RussianToEnglishMapper()
        ]
        
        // Build mappers dictionary from instances
        for mapper in mapperInstances {
            let pair = LayoutPair(from: mapper.fromLayout, to: mapper.toLayout)
            mappers[pair] = mapper.mapping
            
            // Automatically create reverse mapping
            let reversePair = LayoutPair(from: mapper.toLayout, to: mapper.fromLayout)
            var reverseMapping: [Character: Character] = [:]
            for (key, value) in mapper.mapping {
                reverseMapping[value] = key
            }
            mappers[reversePair] = reverseMapping
        }
        
        print("🔤 [Mappers] Loaded \(mappers.count) mapper(s):")
        for (pair, _) in mappers {
            print("   • \(pair.from) → \(pair.to)")
        }
    }
    
    /// Get mapper for a specific layout pair
    private func getMapper(from: String, to: String) -> [Character: Character]? {
        _ = initializedMappers  // Ensure mappers are initialized
        return mappers[LayoutPair(from: from, to: to)]
    }
    
    /// Check if mapper exists for a layout pair
    func hasMapper(from: String, to: String) -> Bool {
        return getMapper(from: from, to: to) != nil
    }
    
    /// Get all available layout pairs
    func availablePairs() -> [(from: String, to: String)] {
        _ = initializedMappers
        return mappers.keys.map { ($0.from, $0.to) }
    }
    
    /// Add a custom mapper at runtime
    func addMapper(_ mapper: LayoutMapper) {
        mapperInstances.append(mapper)
        let pair = LayoutPair(from: mapper.fromLayout, to: mapper.toLayout)
        mappers[pair] = mapper.mapping
        print("🔤 [Mappers] Added custom mapper: \(mapper.fromLayout) → \(mapper.toLayout)")
    }

    // MARK: - Timings (tuned for reliability)

    private let copyTimeoutMs: Int = 350
    private let copyPollStepUs: useconds_t = 3_000
    private let keyDownUpDelayUs: useconds_t = 2_000      // delay between key down and up
    private let keySequenceDelayUs: useconds_t = 15_000   // delay between key sequences
    private let pasteSettleUs: useconds_t = 20_000        // wait after paste
    private let restoreDelay: TimeInterval = 0.12

    // MARK: - Public API

    /// Main entry point: tries Branch A (selection), falls back to Branch B (last word)
    /// - Parameter skipLayoutSwitch: if true, do not switch layout after transformation
    func transformSelectedText(skipLayoutSwitch: Bool = false) {
        print("\n🔄 [TextTransformer] ═══════════════════════════════════")
        print("🔄 [TextTransformer] Transform requested (skipLayout: \(skipLayoutSwitch))")

        let isRussian = currentLayoutIsRussian()
        print("🔄 [TextTransformer] Current layout: \(isRussian ? "RU" : "EN")")

        // Save full clipboard state (including images, files, etc.)
        let clipboard = ClipboardManager.shared
        let savedState = clipboard.saveState()

        // Branch A: Try to detect and transform selected text
        if let selectedText = tryGetSelectedText() {
            print("✅ [TextTransformer] Branch A: selection detected")
            completeBranchA(selectedText: selectedText, isRussian: isRussian, savedState: savedState, skipLayoutSwitch: skipLayoutSwitch)
            return
        }

        // Branch B: Transform last word before cursor (no selection)
        print("🔀 [TextTransformer] Branch A: no selection, trying Branch B (last word)")
        tryBranchB_LastWord(isRussian: isRussian, savedState: savedState, skipLayoutSwitch: skipLayoutSwitch)
    }

    // MARK: - Branch A: Selected Text Transformation

    /// Attempts to copy selected text using Cmd+C
    private func tryGetSelectedText() -> String? {
        print("📋 [Branch A] Attempting to copy selection")

        let clipboard = ClipboardManager.shared

        // Use marker to detect if copy succeeded
        let (marker, markerCount) = clipboard.setMarker()

        // Send Cmd+C with proper timing
        simulateCmdKey(keyCode: 0x08) // C
        usleep(keySequenceDelayUs)

        // Wait for clipboard to change
        guard let copied = clipboard.waitForChange(marker: marker, markerCount: markerCount, timeoutMs: copyTimeoutMs) else {
            print("📋 [Branch A] Copy failed or no selection")
            return nil
        }

        print("📋 [Branch A] Got selection: \"\(copied.prefix(50))\"")
        return copied
    }

    private func completeBranchA(selectedText: String, isRussian: Bool, savedState: ClipboardManager.ClipboardState, skipLayoutSwitch: Bool = false) {
        // Detect language from TEXT content, not keyboard layout
        let textWasRussian = textIsRussian(selectedText)
        let transformed = doTransform(selectedText, fromRussian: textWasRussian)
        print("🔄 [Branch A] Transform: \"\(selectedText.prefix(30))\" → \"\(transformed.prefix(30))\"")

        // Put transformed text to clipboard and paste (single Undo action)
        ClipboardManager.shared.setString(transformed)
        usleep(keySequenceDelayUs)

        // Paste replaces selection automatically
        print("⌨️  [Branch A] Pasting transformed text")
        simulateCmdKey(keyCode: 0x09) // Cmd+V
        usleep(pasteSettleUs)

        // Switch layout if enabled (based on text language, not keyboard)
        // Skip if modifier key was held during double-tap
        if !skipLayoutSwitch && SettingsManager.shared.switchLayoutAfterTransform {
            if let target = resolveTargetLayoutName(textWasRussian: textWasRussian) {
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
    private func tryBranchB_LastWord(isRussian: Bool, savedState: ClipboardManager.ClipboardState, skipLayoutSwitch: Bool = false) {
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
            sendKeyPress(keyCode: 0x7C) // Deselect
            ClipboardManager.shared.restoreState(savedState)
            return
        }

        print("📝 [Branch B] Word: \"\(parsed.word)\", trailing: \(parsed.trailingSpaces.count), leading: \(parsed.leadingSpaces.count)")

        // If there were leading spaces, shrink selection to exclude them
        if !parsed.leadingSpaces.isEmpty {
            print("⌨️  [Branch B] Shrinking selection to exclude \(parsed.leadingSpaces.count) leading spaces")
            for _ in parsed.leadingSpaces {
                sendShiftRight()
                usleep(3_000)
            }
            usleep(keySequenceDelayUs)
        }

        // Transform and paste (detect language from text, not keyboard)
        let textWasRussian = textIsRussian(parsed.word)
        let transformedWord = doTransform(parsed.word, fromRussian: textWasRussian)
        let replacement = transformedWord + parsed.trailingSpaces
        print("🔄 [Branch B] Transform: \"\(parsed.word)\" → \"\(transformedWord)\"")

        // Put to clipboard and paste (single Undo)
        ClipboardManager.shared.setString(replacement)
        usleep(keySequenceDelayUs)

        print("⌨️  [Branch B] Pasting replacement")
        simulateCmdKey(keyCode: 0x09) // Cmd+V
        usleep(pasteSettleUs)

        // Switch layout if enabled (based on text language)
        // Skip if modifier key was held during double-tap
        if !skipLayoutSwitch && SettingsManager.shared.switchLayoutAfterTransform {
            if let target = resolveTargetLayoutName(textWasRussian: textWasRussian) {
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
        let maxIterations = 10 // Safety limit

        for iteration in 0..<maxIterations {
            sendOptionShiftLeft()
            usleep(keySequenceDelayUs)

            guard let selection = copyCurrentSelection() else {
                if fullSelection.isEmpty {
                    print("⚠️  [Branch B] Option+Shift+Left failed - no selection")
                    sendKeyPress(keyCode: 0x7C)
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
            sendKeyPress(keyCode: 0x7C)
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
            sendKeyPress(keyCode: 0x7C) // Deselect
            usleep(keySequenceDelayUs)
            return nil
        }
    }

    /// Copies current selection and returns it
    private func copyCurrentSelection() -> String? {
        let clipboard = ClipboardManager.shared
        let (marker, markerCount) = clipboard.setMarker()

        simulateCmdKey(keyCode: 0x08) // Cmd+C
        usleep(keySequenceDelayUs)

        return clipboard.waitForChange(marker: marker, markerCount: markerCount, timeoutMs: 200)
    }

    /// Checks if selection looks like a valid word (not whole line, no newlines)
    private func isValidWordSelection(_ text: String) -> Bool {
        // Invalid if contains newline
        if text.contains("\n") || text.contains("\r") {
            return false
        }
        // Invalid if too long (probably selected whole line)
        if text.count > 50 {
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
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode: CGKeyCode = 0x7B // Left Arrow

        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = [.maskShift, .maskControl]
        down?.post(tap: .cgAnnotatedSessionEventTap)

        usleep(keyDownUpDelayUs)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = [.maskShift, .maskControl]
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Sends Option+Shift+Left Arrow (select word backward - macOS standard)
    private func sendOptionShiftLeft() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode: CGKeyCode = 0x7B // Left Arrow

        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = [.maskShift, .maskAlternate]
        down?.post(tap: .cgAnnotatedSessionEventTap)

        usleep(keyDownUpDelayUs)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = [.maskShift, .maskAlternate]
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Sends Shift+Right Arrow (shrink selection by one character)
    private func sendShiftRight() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode: CGKeyCode = 0x7C // Right Arrow

        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = [.maskShift]
        down?.post(tap: .cgAnnotatedSessionEventTap)

        usleep(keyDownUpDelayUs)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = [.maskShift]
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    // MARK: - Transform Logic

    /// Detects if text contains Russian characters
    private func textIsRussian(_ text: String) -> Bool {
        // Check if text contains any Cyrillic letters (Unicode range)
        // Do NOT check special characters — only letters!
        for char in text {
            if let scalar = char.unicodeScalars.first {
                // Cyrillic: U+0400–U+04FF
                if scalar.value >= 0x0400 && scalar.value <= 0x04FF {
                    return true
                }
            }
        }
        return false
    }

    /// Transforms text, auto-detecting direction based on text content
    private func doTransform(_ text: String, fromRussian: Bool) -> String {
        // Auto-detect based on text content, not keyboard layout
        let actuallyRussian = textIsRussian(text)
        
        // Get source and target layouts from Command Switch settings
        let settings = SettingsManager.shared
        let fromLayout = actuallyRussian ? settings.leftCommandLanguage : settings.rightCommandLanguage
        let toLayout = actuallyRussian ? settings.rightCommandLanguage : settings.leftCommandLanguage
        
        // Check if mapper exists for this pair
        guard let mapper = getMapper(from: fromLayout, to: toLayout) else {
            print("⚠️ [Transform] No mapper found for \(fromLayout) → \(toLayout)")
            print("🔤 [Transform] Available pairs: \(availablePairs().map { "\($0.from) → \($0.to)" })")
            return text  // Return unchanged if no mapper
        }
        
        print("🔤 [Transform] Using mapper: \(fromLayout) → \(toLayout)")
        return String(text.map { mapper[$0] ?? $0 })
    }

    // MARK: - Keyboard Helpers

    /// Sends a single key press (down + up) with proper timing
    private func sendKeyPress(keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Key down
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.post(tap: .cgAnnotatedSessionEventTap)

        usleep(keyDownUpDelayUs)

        // Key up
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Sends Cmd+Key combination with proper timing
    private func simulateCmdKey(keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Key down with Cmd modifier
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)

        usleep(keyDownUpDelayUs)

        // Key up with Cmd modifier
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    // MARK: - Layout Detection & Switching
    
    private func currentLayoutIsRussian() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return false }
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
        let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        return id.lowercased().contains("russian")
    }
    
    /// Returns target layout name based on text language (what the text WAS before transform)
    private func resolveTargetLayoutName(textWasRussian: Bool) -> String? {
        let settings = SettingsManager.shared

        if textWasRussian {
            // Text was Russian -> transformed to English -> switch to English layout
            let candidate = settings.rightCommandLanguage
            if candidate != "None" { return candidate }
            return "ABC"
        } else {
            // Text was English -> transformed to Russian -> switch to Russian layout
            let candidate = settings.leftCommandLanguage
            if candidate != "None" { return candidate }

            let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
            for s in sources {
                if let ptr = TISGetInputSourceProperty(s, kTISPropertyLocalizedName) {
                    let name = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
                    if name.lowercased().contains("russian") { return name }
                }
            }
            return nil
        }
    }

}
