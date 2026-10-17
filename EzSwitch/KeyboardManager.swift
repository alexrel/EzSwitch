import Cocoa
import Carbon

final class KeyboardManager {
    static let shared = KeyboardManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var _isMonitoring = false
    private var _suppressEvents = false

    private let doubleTapThreshold: TimeInterval = Constants.Timing.doubleTapThreshold
    private let commandMaxHold: TimeInterval = Constants.Timing.commandMaxHold

    // Key codes
    private let leftShiftKeyCode: Int = Constants.KeyCode.leftShift
    private let rightShiftKeyCode: Int = Constants.KeyCode.rightShift
    private let leftOptionKeyCode: Int = Constants.KeyCode.leftOption
    private let rightOptionKeyCode: Int = Constants.KeyCode.rightOption
    private let leftCmdKeyCode: Int = Constants.KeyCode.leftCmd
    private let rightCmdKeyCode: Int = Constants.KeyCode.rightCmd

    private struct KeyState {
        var isDown = false
        var downAt: TimeInterval = 0
        var cancelled = false
    }

    // Per-side state for the chosen layout-switch modifier (defaults to Cmd Left/Right).
    private var leftCmd = KeyState()
    private var rightCmd = KeyState()

    // Transform key tracking
    private var lastTransformKeyRelease: TimeInterval = 0
    private var lastTransformKeyCode: Int = 0
    private var transformKeyDown = false
    private var transformKeyCancelled = false

    // Track individual Shift keys for "hold one + double-tap other" detection
    private var leftShiftDown = false
    private var rightShiftDown = false

    // Word-level substitution buffer
    private var wordBuffer: String = ""
    /// True while we are programmatically sending backspaces + Cmd+V so
    /// our own synthetic events do not mutate `wordBuffer`.
    private var isReplacingWord = false
    /// Last layout we switched TO (via Cmd/Option tap or initial). Used as
    /// a fallback when the live layout query returns something we don't know.
    private var currentLayoutID: String = ""

    // Key codes
    private let deleteKeyCode: Int = Constants.KeyCode.delete // kVK_Delete (backspace)

    private init() {
        // Clear word buffer whenever the user switches active applications
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.wordBuffer.removeAll()
        }
    }

    func startMonitoring(suppressEvents: Bool = false) {
        // If already monitoring, check if we need to recreate the tap
        if _isMonitoring {
            if _suppressEvents != suppressEvents {
                stopMonitoring()
            } else {
                return
            }
        }

        _suppressEvents = suppressEvents

        let mask = (1 << CGEventType.keyDown.rawValue) |
                   (1 << CGEventType.keyUp.rawValue) |
                   (1 << CGEventType.flagsChanged.rawValue)

        // For event suppression use .defaultTap, otherwise .listenOnly
        let tapOptions: CGEventTapOptions = suppressEvents ? .defaultTap : .listenOnly

        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: tapOptions,
            eventsOfInterest: CGEventMask(mask),
            callback: { (_, type, event, _) -> Unmanaged<CGEvent>? in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = KeyboardManager.shared.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                        print("⚠️ [KeyboardManager] Event tap re-enabled after timeout")
                    }
                    return Unmanaged.passUnretained(event)
                }
                return KeyboardManager.shared.handle(type: type, event: event)
            },
            userInfo: nil
        )

        guard let tap = eventTap else {
            print("⚠️ KeyboardManager: failed to create event tap (Accessibility permission required)")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        _isMonitoring = true

        print("⌨️  KeyboardManager: monitoring started (suppress=\(suppressEvents))")
    }

    func stopMonitoring() {
        guard let tap = eventTap else { return }

        CGEvent.tapEnable(tap: tap, enable: false)

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        CFMachPortInvalidate(tap)

        eventTap = nil
        runLoopSource = nil
        _isMonitoring = false

        print("⌨️  KeyboardManager: monitoring stopped")
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let now = CFAbsoluteTimeGetCurrent()
        let switchMod = SettingsManager.shared.switchModifier

        // Ignore synthetic keystrokes while we are actively replacing a word
        if isReplacingWord {
            return Unmanaged.passUnretained(event)
        }

        // 1) Any regular key during switch-modifier -> cancel
        if type == .keyDown {
            if leftCmd.isDown { leftCmd.cancelled = true }
            if rightCmd.isDown { rightCmd.cancelled = true }
            if transformKeyDown { transformKeyCancelled = true }

            // Word-level substitution: append printable chars / commit on separator
            if SettingsManager.shared.enableWordSubstitution {
                // Configurable hotkey: remember the current word. Suppress the key
                // so it doesn't appear in the target text field.
                let hotkey = SettingsManager.shared.wordRememberHotkey
                if hotkey.isSet,
                   keyCode == Int(hotkey.keyCode),
                   hotkey.matches(flags: flags) {
                    rememberCurrentWord()
                    return nil
                }

                // Backspace: pop last character from buffer
                if keyCode == deleteKeyCode {
                    if !wordBuffer.isEmpty {
                        wordBuffer.removeLast()
                    }
                    return Unmanaged.passUnretained(event)
                }

                // Navigation / Escape / Tab keys: clear word buffer
                if isBufferResetKey(keyCode) {
                    wordBuffer.removeAll()
                    return Unmanaged.passUnretained(event)
                }

                // Only treat as text if no Cmd/Ctrl/Opt is held. Otherwise
                // shortcuts like ⌘C or ⌘Z reset the buffer.
                let nonTextModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
                if flags.intersection(nonTextModifiers).isEmpty {
                    if let scalar = unicodeScalar(forKeyCode: keyCode, flags: flags, event: event) {
                        if isWordSeparator(scalar) {
                            if tryCommitWordBuffer(separator: String(scalar)) {
                                // Separator event is suppressed; replacement + separator
                                // will be pasted asynchronously.
                                return nil
                            }
                        } else {
                            wordBuffer.append(Character(scalar))
                        }
                    }
                } else {
                    wordBuffer.removeAll()
                }
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            // 2) Modifiers during switch-modifier -> cancel (the other modifier keys
            //    and Ctrl/Fn). The transform key uses a different code path, so it
            //    stays out of the conflict.
            let forbidden: CGEventFlags = [.maskShift, .maskAlternate, .maskControl, .maskSecondaryFn]
            // Strip out the modifier we are actually watching — the modifier we own
            // is expected to be present while its key is held.
            let ourMask: CGEventFlags = switchMod.isCommand ? .maskCommand : .maskAlternate
            let otherModifiers = flags.subtracting(ourMask)
            if leftCmd.isDown || rightCmd.isDown {
                if !otherModifiers.intersection(forbidden).isEmpty {
                    if leftCmd.isDown { leftCmd.cancelled = true }
                    if rightCmd.isDown { rightCmd.cancelled = true }
                }
            }

            // 3) Switch-modifier logic (Command or Option, left/right as configured)
            let isDown = flags.contains(ourMask)
            if switchMod.tracksLeft && keyCode == switchMod.leftKeyCode {
                updateCmd(&leftCmd, isDown: isDown, now: now, lang: SettingsManager.shared.leftCommandLanguage)
            } else if switchMod.tracksRight && keyCode == switchMod.rightKeyCode {
                updateCmd(&rightCmd, isDown: isDown, now: now, lang: SettingsManager.shared.rightCommandLanguage)
            }

            // 4) Transform key logic (Shift or Option)
            if SettingsManager.shared.enableTransformKey {
                let result = handleTransformKey(keyCode: keyCode, flags: flags, now: now)
                if result.shouldSuppress && _suppressEvents {
                    return nil // Suppress event
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    /// Handles transform key
    /// Returns: (triggered: whether transformation was triggered, shouldSuppress: whether to suppress the event)
    private func handleTransformKey(keyCode: Int, flags: CGEventFlags, now: TimeInterval) -> (triggered: Bool, shouldSuppress: Bool) {
        let settings = SettingsManager.shared
        let keyType = settings.transformKeyType

        // Determine which keys to track
        let isShiftBased = keyType.isShift
        let relevantMask: CGEventFlags = isShiftBased ? .maskShift : .maskAlternate
        let leftKeyCode = isShiftBased ? leftShiftKeyCode : leftOptionKeyCode
        let rightKeyCode = isShiftBased ? rightShiftKeyCode : rightOptionKeyCode

        // Check if event is for our key
        let isRelevantKey: Bool
        switch keyType {
        case .doubleLeftShift, .doubleLeftOption:
            isRelevantKey = (keyCode == leftKeyCode)
        case .doubleRightShift, .doubleRightOption:
            isRelevantKey = (keyCode == rightKeyCode)
        case .doubleBothShift, .doubleBothOption:
            isRelevantKey = (keyCode == leftKeyCode || keyCode == rightKeyCode)
        }

        guard isRelevantKey else {
            // Other modifiers - cancel if our key is held
            if transformKeyDown {
                let otherModifiers: CGEventFlags = isShiftBased
                    ? [.maskAlternate, .maskControl, .maskCommand]
                    : [.maskShift, .maskControl, .maskCommand]
                if !flags.intersection(otherModifiers).isEmpty {
                    transformKeyCancelled = true
                }
            }
            return (false, false)
        }

        let isKeyDown = flags.contains(relevantMask)

        // Track individual Shift keys state
        if isShiftBased {
            if keyCode == leftShiftKeyCode {
                leftShiftDown = isKeyDown
            } else if keyCode == rightShiftKeyCode {
                rightShiftDown = isKeyDown
            }
        }

        if isKeyDown && !transformKeyDown {
            // Key down
            transformKeyDown = true
            transformKeyCancelled = false
            return (false, false)
        } else if !isKeyDown && transformKeyDown {
            // Key up
            transformKeyDown = false

            if transformKeyCancelled {
                lastTransformKeyRelease = 0
                return (false, false)
            }

            // Check for double tap
            let sameKey = (keyCode == lastTransformKeyCode) ||
                          (keyType == .doubleBothShift || keyType == .doubleBothOption)

            if sameKey && (now - lastTransformKeyRelease) < doubleTapThreshold {
                // Double tap detected!
                lastTransformKeyRelease = 0
                lastTransformKeyCode = 0

                // Check if OTHER Shift is held (for "no layout switch" mode)
                // If right Shift was double-tapped, check if left is held, and vice versa
                let otherShiftHeld: Bool
                if isShiftBased {
                    if keyCode == leftShiftKeyCode {
                        // Double-tapped left → check right
                        otherShiftHeld = rightShiftDown
                    } else if keyCode == rightShiftKeyCode {
                        // Double-tapped right → check left
                        otherShiftHeld = leftShiftDown
                    } else {
                        otherShiftHeld = false
                    }
                } else {
                    otherShiftHeld = false
                }

                let skipLayoutSwitch = otherShiftHeld
                print("⌨️  Double \(keyType.shortName) detected! (skipLayout: \(skipLayoutSwitch), L:\(leftShiftDown) R:\(rightShiftDown))")

                DispatchQueue.main.async {
                    TextTransformer.shared.transformSelectedText(skipLayoutSwitch: skipLayoutSwitch)
                }

                return (true, true) // Suppress second tap
            } else {
                lastTransformKeyRelease = now
                lastTransformKeyCode = keyCode
                return (false, false)
            }
        }

        return (false, false)
    }

    private func updateCmd(_ state: inout KeyState, isDown: Bool, now: TimeInterval, lang: String) {
        guard SettingsManager.shared.commandSwitchEnabled else { return }

        if isDown && !state.isDown {
            state = KeyState(isDown: true, downAt: now, cancelled: false)
        } else if !isDown && state.isDown {
            if !state.cancelled && (now - state.downAt) < commandMaxHold {
                currentLayoutID = lang
                switchToLayout(named: lang)
            }
            state.isDown = false
        }
    }

    func switchToLayout(named: String) {
        if named == Constants.Default.noneLanguage { return }

        let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
        for s in sources {
            if let ptr = TISGetInputSourceProperty(s, kTISPropertyLocalizedName) {
                let name = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
                if name == named {
                    TISSelectInputSource(s)
                    break
                }
            }
        }
    }

    // MARK: - Word-level substitution

    /// Keys that move the cursor or cancel typing without inserting text.
    private func isBufferResetKey(_ keyCode: Int) -> Bool {
        switch keyCode {
        case Constants.KeyCode.leftArrow,
             Constants.KeyCode.rightArrow,
             Constants.KeyCode.upArrow,
             Constants.KeyCode.downArrow,
             Constants.KeyCode.escape,
             Constants.KeyCode.home,
             Constants.KeyCode.end,
             Constants.KeyCode.pageUp,
             Constants.KeyCode.pageDown,
             Constants.KeyCode.forwardDelete:
            return true
        default:
            return false
        }
    }

    /// Characters that end a word buffer.
    private func isWordSeparator(_ scalar: Unicode.Scalar) -> Bool {
        // Whitespace + common sentence punctuation
        switch scalar {
        case " ", "\n", "\t", "\r",
             ".", ",", ";", ":", "!", "?", "\"" , "'",
             "(", ")", "[", "]", "{", "}",
             "<", ">", "/", "\\", "|", "-", "_", "=", "+":
            return true
        default:
            return false
        }
    }

    /// Translate a key code + modifier flags into a Unicode scalar using
    /// the current keyboard layout via UCKeyTranslate (with proper UCTModifier
    /// bitmasks) and falling back to the CGEvent's native Unicode string.
    private func unicodeScalar(forKeyCode keyCode: Int, flags: CGEventFlags, event: CGEvent) -> Unicode.Scalar? {
        // 1) UCKeyTranslate expects the compact UCTModifier bitfield (shift = 0x02, option = 0x08)
        var mods: UInt32 = Constants.UCTModifier.none
        if flags.contains(.maskShift)     { mods |= Constants.UCTModifier.shift }
        if flags.contains(.maskAlternate) { mods |= Constants.UCTModifier.option }

        let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
            ?? TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()

        if let source = inputSource,
           let layoutDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPtr).takeUnretainedValue() as Data
            if let layoutPtr = layoutData.withUnsafeBytes({ $0.baseAddress }) {
                let layout = layoutPtr.assumingMemoryBound(to: UCKeyboardLayout.self)
                var deadKeyState: UInt32 = 0
                let maxStringLength = 4
                var chars = [UniChar](repeating: 0, count: maxStringLength)
                var actualLength: Int = 0

                let status = UCKeyTranslate(
                    layout,
                    UInt16(keyCode),
                    UInt16(kUCKeyActionDown),
                    mods,
                    UInt32(LMGetKbdType()),
                    UInt32(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    maxStringLength,
                    &actualLength,
                    &chars
                )

                if status == noErr, actualLength > 0 {
                    let raw = String(utf16CodeUnits: &chars, count: actualLength)
                    if let scalar = raw.unicodeScalars.first {
                        return scalar
                    }
                }
            }
        }

        // 2) Fallback: read the Unicode string directly attached to the CGEvent
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        if length > 0 {
            var buffer = [UniChar](repeating: 0, count: length)
            event.keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &length, unicodeString: &buffer)
            let str = String(utf16CodeUnits: buffer, count: length)
            return str.unicodeScalars.first
        }

        return nil
    }

    /// End-of-word: try to find a match and auto-replace.
    /// Returns `true` if a substitution was found and scheduled (caller should suppress separator event).
    private func tryCommitWordBuffer(separator: String) -> Bool {
        let word = wordBuffer
        wordBuffer = ""
        guard word.count >= Constants.WordSub.minAutoReplaceLength,
              word.contains(where: { $0.isLetter }) else { return false }
        guard let pair = currentActivePair() else { return false }
        guard let result = WordMapperStore.shared.findMatch(word: word, pair: pair) else { return false }

        let wordLength = word.count
        let replacement = result.replacement

        print("✨ [WordSub] Auto-replacing \"\(word)\" → \"\(replacement)\"")

        // Perform deletion + paste asynchronously on main thread so the event tap
        // callback returns `nil` immediately (suppressing the separator key).
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.replaceTypedWord(
                originalLength: wordLength,
                separator: separator,
                with: replacement
            )
        }
        return true
    }

    /// Configurable hotkey handler. Saves the currently buffered word; if the
    /// buffer is empty, falls back to the user's selected text (via Cmd+C
    /// round-trip through the pasteboard). In both cases the typed or
    /// selected word is also replaced in place — without switching the
    /// keyboard layout.
    private func rememberCurrentWord() {
        let word = wordBuffer
        if !word.isEmpty {
            wordBuffer = ""
            if let pair = currentActivePair() {
                saveWordAsMapping(word, pair: pair)
                let other = applyCharacterMapping(word, from: pair.from, to: pair.to)
                if !other.isEmpty && other != word {
                    let wordLength = word.count
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.isReplacingWord = true
                        for _ in 0..<wordLength {
                            self.simulateKeyDownUp(keyCode: self.deleteKeyCode, modifierFlags: [])
                            usleep(Constants.Timing.backspaceDelayUs)
                        }
                        usleep(Constants.Timing.keySequenceDelayUs)
                        self.pasteText(other)
                        self.isReplacingWord = false
                    }
                }
            }
            return
        }
        // No buffer — try to capture the user's selected text.
        captureSelectedText { [weak self] captured in
            guard let self = self else { return }
            guard let raw = captured?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return }
            // Multi-word selection: take only the last whitespace-separated token.
            let token = raw.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? raw
            guard token.count >= 1 else { return }
            guard let pair = self.currentActivePair() else { return }
            self.saveWordAsMapping(token, pair: pair)
            // Also replace the selection (still active after Cmd+C).
            let other = self.applyCharacterMapping(token, from: pair.from, to: pair.to)
            if !other.isEmpty && other != token {
                self.isReplacingWord = true
                self.pasteText(other)
                self.isReplacingWord = false
            }
        }
    }

    /// Persist a one-way mapping `word → otherLayoutEquivalent` for the pair.
    /// `pair.from` is the layout the user typed in, `pair.to` is the other.
    private func saveWordAsMapping(_ word: String, pair: LayoutPair) {
        let other = applyCharacterMapping(word, from: pair.from, to: pair.to)
        guard !other.isEmpty, other != word else {
            print("💡 [WordSub] Skipped remember '\(word)' — no character mapping available")
            return
        }
        WordMapperStore.shared.set(source: word, target: other, for: pair)
        print("💡 [WordSub] Saved '\(word)' → '\(other)' for pair \(pair.from)|\(pair.to)")
    }

    /// The pair whose `from` is the current layout. If the current layout is
    /// the "to" side, returns the inverse pair. Returns nil if the current
    /// layout doesn't match either side of the configured pair.
    private func currentActivePair() -> LayoutPair? {
        let settings = SettingsManager.shared
        let left = settings.leftCommandLanguage
        let right = settings.rightCommandLanguage
        guard !left.isEmpty, !right.isEmpty,
              left != Constants.Default.noneLanguage,
              right != Constants.Default.noneLanguage,
              left != right else {
            return nil
        }
        // Use the live layout first (handles the common case of typing
        // without ever tapping Cmd), fall back to the cached value.
        let current = currentLayoutName() ?? currentLayoutID
        if current == left { return LayoutPair(from: left, to: right) }
        if current == right { return LayoutPair(from: right, to: left) }
        return LayoutPair(from: left, to: right)
    }

    /// Localized name of the keyboard layout currently driving key events.
    private func currentLayoutName() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// Erase `originalLength` chars (since the separator key event was already
    /// suppressed), then paste `replacement + separator` via the clipboard.
    private func replaceTypedWord(
        originalLength: Int,
        separator: String,
        with replacement: String
    ) {
        isReplacingWord = true
        for _ in 0..<originalLength {
            simulateKeyDownUp(keyCode: deleteKeyCode, modifierFlags: [])
            usleep(Constants.Timing.backspaceDelayUs)
        }
        usleep(Constants.Timing.keySequenceDelayUs)
        pasteText(replacement + separator)
        isReplacingWord = false
    }

    private func simulateKeyDownUp(keyCode: Int, modifierFlags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: UInt16(keyCode), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: UInt16(keyCode), keyDown: false)
        down?.flags = modifierFlags
        up?.flags = modifierFlags
        down?.post(tap: .cgAnnotatedSessionEventTap)
        usleep(Constants.Timing.keyDownUpDelayUs)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Send a Cmd+V key event to `.cgAnnotatedSessionEventTap` so it goes
    /// directly to the target app without re-entering our HID event tap.
    private func simulateCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = UInt16(Constants.KeyCode.v)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        usleep(Constants.Timing.keyDownUpDelayUs)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Set `text` on the pasteboard, simulate Cmd+V, then restore the
    /// original pasteboard contents a moment later.
    private func pasteText(_ text: String) {
        let savedState = ClipboardManager.shared.saveState()
        ClipboardManager.shared.setString(text)
        usleep(Constants.Timing.keySequenceDelayUs)

        // If the user is currently holding a hotkey modifier (e.g. ⌘⇧ from
        // the word-remember hotkey), our Cmd+V would be interpreted as
        // ⌘⇧V by the target app. Defer briefly so the modifier has a
        // chance to be released first.
        let currentFlags = CGEventSource.flagsState(.combinedSessionState)
        let problematic: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        let needsDefer = !currentFlags.intersection(problematic).isEmpty

        if needsDefer {
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Timing.pasteCmdVDeferSec) { [weak self] in
                self?.simulateCmdV()
            }
        } else {
            simulateCmdV()
            usleep(Constants.Timing.pasteSettleUs)
        }

        // Restore the original clipboard once the paste has had time to
        // settle, but only if the user hasn't copied something else in
        // the meantime.
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Timing.pasteRestoreDelaySec) {
            if NSPasteboard.general.string(forType: .string) == text {
                ClipboardManager.shared.restoreState(savedState)
            }
        }
    }

    /// Apply the character-level preset for `from ↔ to` to `word` char by char.
    /// Prefers the user-selected preset for the pair, falling back to any
    /// preset registered for the pair, and automatically inverts when typing in `active.toLayout`.
    private func applyCharacterMapping(_ word: String, from: String, to: String) -> String {
        let store = MapperStore.shared
        let settings = SettingsManager.shared
        let pair = LayoutPair(from: from, to: to)
        let presets = store.presets(for: pair)

        let active: LayoutMapperPreset?
        if let presetID = settings.selectedPresetId(for: from, to),
           let preset = presets.first(where: { $0.id == presetID }) {
            active = preset
        } else {
            active = presets.first
        }
        guard let active = active else { return word }

        let forwardMap = active.characterMapping()
        let mapping: [Character: String]
        if active.fromLayout == from {
            mapping = forwardMap
        } else {
            var reversed: [Character: String] = [:]
            for (k, v) in forwardMap where v.count == 1 {
                if let first = v.first {
                    reversed[first] = String(k)
                }
            }
            mapping = reversed
        }

        var result = ""
        for ch in word {
            if let mapped = mapping[ch] {
                result.append(mapped)
            } else {
                result.append(ch)
            }
        }
        return result
    }

    /// Round-trip the user's current selection through the pasteboard.
    /// Saves existing pasteboard contents, simulates Cmd+C, polls for the
    /// pasteboard to change, then restores the original contents.
    private func captureSelectedText(completion: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            let pasteboard = NSPasteboard.general
            let savedChangeCount = pasteboard.changeCount
            var savedContents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in pasteboard.types ?? [] {
                if let data = pasteboard.data(forType: type) {
                    savedContents[type] = data
                }
            }

            // Simulate Cmd+C
            let source = CGEventSource(stateID: .combinedSessionState)
            let cKey = UInt16(Constants.KeyCode.c)
            let down = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cgAnnotatedSessionEventTap)
            usleep(Constants.Timing.captureKeyDelayUs)
            up?.post(tap: .cgAnnotatedSessionEventTap)

            // Wait up to captureTimeoutSec for the target app to write to the pasteboard.
            let deadline = Date().addingTimeInterval(Constants.Timing.captureTimeoutSec)
            var captured: String?
            while Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(Constants.Timing.capturePollStepSec))
                if pasteboard.changeCount != savedChangeCount {
                    captured = pasteboard.string(forType: .string)
                    break
                }
            }

            // Restore pasteboard (clear + replay saved types).
            pasteboard.clearContents()
            for (type, data) in savedContents {
                pasteboard.setData(data, forType: type)
            }

            completion(captured)
        }
    }
}

private extension LayoutPair {
    /// The "other" layout in the pair, relative to `current`.
    func other(_ current: String) -> String {
        if current == from { return to }
        if current == to { return from }
        return to
    }
}
