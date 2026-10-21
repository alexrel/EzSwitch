import Cocoa
import Carbon
import OSLog

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
    private var wordBuffer = TypedWordBuffer()
    private var terminalReplacementPID: pid_t?
    private var terminalFocusedElement: AXUIElement?
    private var deferredTerminalEvents: [(event: CGEvent, scalar: Unicode.Scalar?)] = []
    /// While replacement is in progress, pass events through without updating
    /// wordBuffer or modifier tracking. This also applies to real user input.
    private var isReplacingWord = false
    /// Serial queue for long synthetic-input sequences (backspaces, Cmd+C
    /// round-trip, paste). These block for tens of milliseconds with `usleep`
    /// and must not run on the main thread: the event tap lives on the main
    /// run loop, so blocking main delays delivery of every real keystroke.
    private let workQueue = CGEventSynthesizer.workQueue
    /// Last observed or requested layout, as a stable input source ID.
    /// Reads from TIS refresh this cached value after system layout changes.
    public private(set) var currentLayoutID: String = ""
    /// Previous layout before the current switch (used to determine where we came from).
    public private(set) var previousLayoutID: String = ""

    // Key codes
    private let deleteKeyCode: Int = Constants.KeyCode.delete // kVK_Delete (backspace)

    private init() {
        _ = currentInputSourceID()

        // Observe layout changes system-wide from Carbon / macOS.
        // The distributed notification is delivered on an arbitrary thread,
        // while `currentLayoutID` / `previousLayoutID` are read from the main
        // thread (event tap, SwiftUI) — hop to main before touching them.
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDistributedCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                DispatchQueue.main.async {
                    let manager = Unmanaged<KeyboardManager>.fromOpaque(observer).takeUnretainedValue()
                    _ = manager.currentInputSourceID()
                }
            },
            kTISNotifySelectedKeyboardInputSourceChanged,
            nil,
            .deliverImmediately
        )

        // Clear word buffer whenever the user switches active applications
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.wordBuffer.reset()
            _ = self?.currentInputSourceID()
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

        let eventTypes: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseUp, .rightMouseUp, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged
        ]
        let mask = eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

        // For event suppression use .defaultTap, otherwise .listenOnly
        let tapOptions: CGEventTapOptions = suppressEvents ? .defaultTap : .listenOnly

        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: tapOptions,
            eventsOfInterest: CGEventMask(mask),
            callback: { (_, type, event, _) -> Unmanaged<CGEvent>? in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    KeyboardManager.shared.wordBuffer.reset()
                    if let tap = KeyboardManager.shared.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                        Log.permissions.error("Event tap was disabled by the system (\(String(describing: type), privacy: .public)) and re-enabled — keys were dropped while it was off")
                    }
                    return Unmanaged.passUnretained(event)
                }
                return KeyboardManager.shared.handle(type: type, event: event)
            },
            userInfo: nil
        )

        guard let tap = eventTap else {
            Log.permissions.error("Failed to create the event tap — Accessibility permission is required. EzSwitch will not react to any key.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        _isMonitoring = true

        Log.permissions.debug("Event tap started (suppress=\(suppressEvents ? "on" : "off", privacy: .public))")
    }

    func stopMonitoring() {
        leftCmd = KeyState()
        rightCmd = KeyState()
        lastTransformKeyRelease = 0
        lastTransformKeyCode = 0
        transformKeyDown = false
        transformKeyCancelled = false
        leftShiftDown = false
        rightShiftDown = false
        wordBuffer.reset()
        guard let tap = eventTap else { return }

        CGEvent.tapEnable(tap: tap, enable: false)

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        CFMachPortInvalidate(tap)

        eventTap = nil
        runLoopSource = nil
        _isMonitoring = false

        Log.permissions.debug("Event tap stopped")
    }

    /// True when EzSwitch itself is the frontmost app (popover, mapper
    /// window, hotkey recorder sheet). Word substitution must stay inert
    /// there: the tap still sees keystrokes typed into our own text fields,
    /// and auto-replacing them with synthetic backspaces + paste would
    /// corrupt what the user is typing in our UI.
    private var isFrontmostAppSelf: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    private func handle(type: CGEventType, event: CGEvent, capturedScalar: Unicode.Scalar? = nil) -> Unmanaged<CGEvent>? {
        // Keep real input ordered after the terminal's delete/paste transaction.
        if terminalReplacementPID != nil {
            if let copy = event.copy() {
                let scalar = capturedScalar ?? (type == .keyDown ? unicodeScalar(
                    forKeyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)), flags: event.flags, event: event
                ) : nil)
                deferredTerminalEvents.append((copy, scalar))
            }
            return nil
        }
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            wordBuffer.reset()
            return Unmanaged.passUnretained(event)
        }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let now = CFAbsoluteTimeGetCurrent()
        let switchMod = SettingsManager.shared.switchModifier

        // Bypass state updates while the replacement sequence is running.
        if isReplacingWord {
            return Unmanaged.passUnretained(event)
        }

        // 1) Any regular key during switch-modifier -> cancel
        if type == .keyDown {
            if leftCmd.isDown { leftCmd.cancelled = true }
            if rightCmd.isDown { rightCmd.cancelled = true }
            if transformKeyDown { transformKeyCancelled = true }

            // Word-level substitution: append printable chars / commit on separator.
            // Skipped entirely while our own UI is frontmost (see isFrontmostAppSelf).
            let settings = SettingsManager.shared
            let isTerminal = AppConfigRegistry.isTerminal(bundleID: AppConfigRegistry.frontmostAppBundleId())
            if (settings.enableWordSubstitution || (settings.enableTransformKey && isTerminal)), !isFrontmostAppSelf {
                // Configurable hotkey: remember the current word. Suppress the key
                // so it doesn't appear in the target text field.
                let hotkey = SettingsManager.shared.wordRememberHotkey
                if settings.enableWordSubstitution, hotkey.isSet,
                   keyCode == Int(hotkey.keyCode),
                   hotkey.matches(flags: flags) {
                    rememberCurrentWord()
                    return nil
                }

                // Backspace: pop last character from buffer
                if keyCode == deleteKeyCode {
                    if flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
                        wordBuffer.backspace()
                    } else { wordBuffer.reset() }
                    return Unmanaged.passUnretained(event)
                }

                // Navigation and Escape keys clear the word buffer.
                if isBufferResetKey(keyCode) {
                    wordBuffer.reset()
                    return Unmanaged.passUnretained(event)
                }

                // Only treat as text if no Cmd/Ctrl/Opt is held. Otherwise
                // shortcuts like ⌘C or ⌘Z reset the buffer.
                let nonTextModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
                if flags.intersection(nonTextModifiers).isEmpty {
                    if let scalar = capturedScalar ?? unicodeScalar(forKeyCode: keyCode, flags: flags, event: event) {
                        if TypedWordBuffer.isSeparator(scalar) {
                            if settings.enableWordSubstitution,
                               tryCommitWordBuffer(separator: String(scalar), event: event) {
                                // Separator event is suppressed; replacement + separator
                                // will be pasted asynchronously.
                                return nil
                            }
                        }
                        wordBuffer.append(scalar)
                    }
                } else {
                    wordBuffer.reset()
                }
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            // 2) Other modifiers cancel a pending layout switch.
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
                updateCmd(&leftCmd, isDown: isDown, now: now, layoutID: SettingsManager.shared.leftCommandLayout)
            } else if switchMod.tracksRight && keyCode == switchMod.rightKeyCode {
                updateCmd(&rightCmd, isDown: isDown, now: now, layoutID: SettingsManager.shared.rightCommandLayout)
            }

            // 4) Transform key logic (Shift or Option)
            if SettingsManager.shared.enableTransformKey {
                let result = handleTransformKey(keyCode: keyCode, flags: flags, now: now)
                if result.shouldSuppress && SettingsManager.shared.suppressTransformKey && _suppressEvents {
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
                Log.transform.debug("Double \(keyType.shortName, privacy: .public) detected (skipLayout=\(skipLayoutSwitch ? "yes" : "no", privacy: .public), left=\(self.leftShiftDown ? "down" : "up", privacy: .public), right=\(self.rightShiftDown ? "down" : "up", privacy: .public))")

                if AppConfigRegistry.isTerminal(bundleID: AppConfigRegistry.frontmostAppBundleId()) {
                    // Lock the observed text before the next input event can change it.
                    transformTerminalWord(skipLayoutSwitch: skipLayoutSwitch)
                } else {
                    DispatchQueue.main.async {
                        TextTransformer.shared.transformSelectedText(skipLayoutSwitch: skipLayoutSwitch)
                    }
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

    /// Track one switch-modifier key and switch on release.
    ///
    /// - Parameter layoutID: stable input source id bound to this key.
    private func updateCmd(_ state: inout KeyState, isDown: Bool, now: TimeInterval, layoutID: String) {
        guard SettingsManager.shared.commandSwitchEnabled else { return }

        if isDown && !state.isDown {
            state = KeyState(isDown: true, downAt: now, cancelled: false)
        } else if !isDown && state.isDown {
            if !state.cancelled && (now - state.downAt) < commandMaxHold {
                // Let switchToLayout update tracking: assigning currentLayoutID
                // here would lose the previous layout before the switch is recorded.
                switchToLayout(id: layoutID)
            }
            state.isDown = false
        }
    }

    /// Switch to the layout with this stable id and record it as current.
    ///
    /// Prefer input source IDs because display names depend on system language.
    /// Legacy names can still resolve when they match the current locale.
    func switchToLayout(id: String) {
        guard !id.isEmpty, id != Constants.Default.noneLanguage else { return }
        guard let source = KeyboardLayoutUtility.inputSource(forLayout: id) else { return }

        // Prefer the id TIS reports over the requested value: it is the exact
        // identity of the source we are about to select, including when the
        // requested value was a legacy localized name.
        let selectedID = KeyboardLayoutUtility.inputSourceID(of: source) ?? id
        if !currentLayoutID.isEmpty, currentLayoutID != selectedID {
            previousLayoutID = currentLayoutID
        }
        currentLayoutID = selectedID
        TISSelectInputSource(source)
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

    /// Translate a key code + modifier flags into a Unicode scalar using
    /// the current keyboard layout via UCKeyTranslate (with proper UCTModifier
    /// bitmasks) and falling back to the CGEvent's native Unicode string.
    private func unicodeScalar(forKeyCode keyCode: Int, flags: CGEventFlags, event: CGEvent) -> Unicode.Scalar? {
        // 1) UCKeyTranslate expects the compact UCTModifier bitfield (shift = 0x02, option = 0x08)
        var mods: UInt32 = Constants.UCTModifier.none
        if flags.contains(.maskShift)     { mods |= Constants.UCTModifier.shift }
        if flags.contains(.maskAlternate) { mods |= Constants.UCTModifier.option }
        if flags.contains(.maskAlphaShift) { mods |= UInt32(alphaLock >> 8) }

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
    private func tryCommitWordBuffer(separator: String, event: CGEvent) -> Bool {
        let word = wordBuffer.currentWord
        guard word.count >= Constants.WordSub.minAutoReplaceLength,
              word.contains(where: { $0.isLetter }) else { return false }
        guard let pair = currentActivePair() else { return false }
        guard let result = WordMapperStore.shared.findMatch(word: word, pair: pair) else { return false }

        let wordLength = word.count
        let replacement = result.replacement
        let targetLayout = result.targetLayout

        if AppConfigRegistry.isTerminal(bundleID: AppConfigRegistry.frontmostAppBundleId()) {
            guard TerminalInput.isSafeReplacement(replacement),
                  let separatorEvent = event.copy(), beginTerminalReplacement() else { return false }
            wordBuffer.reset()
            let replay = TerminalInput.replaysSeparator(separator)
            replaceTerminalWord(original: word, replacement: replacement + (replay ? "" : separator),
                                separatorEvent: replay ? separatorEvent : nil, targetLayout: targetLayout)
            return true
        }
        wordBuffer.reset()

        Log.words.debug("Auto-replacing \"\(word, privacy: .public)\" → \"\(replacement, privacy: .public)\" (targetLayout=\(targetLayout ?? "none", privacy: .public))")

        // Perform deletion + paste on a background queue: the sequence blocks
        // for tens of milliseconds (usleep between keystrokes) and would
        // otherwise stall key delivery on the main thread. The event-tap
        // callback returns `nil` immediately (suppressing the separator key).
        // `isReplacingWord` guards on the tap's thread, so flip it there too.
        isReplacingWord = true
        workQueue.async { [weak self] in
            guard let self = self else { return }
            self.replaceTypedWord(
                originalLength: wordLength,
                separator: separator,
                with: replacement
            )
            // Give the paste a moment to land before the input source flips —
            // otherwise the target app can receive the pasted text under the
            // new layout.
            if targetLayout != nil {
                Thread.sleep(forTimeInterval: Constants.Timing.layoutSwitchDelaySec)
            }
            DispatchQueue.main.async { [weak self] in
                self?.isReplacingWord = false
                if let target = targetLayout {
                    self?.switchToLayout(id: target)
                }
            }
        }
        return true
    }

    /// Configurable hotkey handler. Saves the currently buffered word; if the
    /// buffer is empty, falls back to the user's selected text (via Cmd+C
    /// round-trip through the pasteboard). In both cases the typed or
    /// selected word is also replaced in place and switches to the target layout.
    private func rememberCurrentWord() {
        let word = wordBuffer.currentWord
        if !word.isEmpty {
            if AppConfigRegistry.isTerminal(bundleID: AppConfigRegistry.frontmostAppBundleId()) {
                guard let pair = currentActivePair() else { return }
                let other = applyCharacterMapping(word, from: pair.from, to: pair.to)
                guard other != word, TerminalInput.isSafeReplacement(other), beginTerminalReplacement() else { return }
                saveWordAsMapping(word, pair: pair)
                replaceTerminalWord(original: word, replacement: other, targetLayout: pair.to)
                return
            }
            wordBuffer.reset()
            if let pair = currentActivePair() {
                saveWordAsMapping(word, pair: pair)
                let other = applyCharacterMapping(word, from: pair.from, to: pair.to)
                if !other.isEmpty && other != word {
                    let wordLength = word.count
                    isReplacingWord = true
                    workQueue.async { [weak self] in
                        guard let self = self else { return }
                        for _ in 0..<wordLength {
                            self.simulateKeyDownUp(keyCode: self.deleteKeyCode, modifierFlags: [])
                            usleep(Constants.Timing.backspaceDelayUs)
                        }
                        usleep(Constants.Timing.keySequenceDelayUs)
                        self.pasteText(other)
                        Thread.sleep(forTimeInterval: Constants.Timing.layoutSwitchDelaySec)

                        DispatchQueue.main.async { [weak self] in
                            self?.isReplacingWord = false
                            self?.switchToLayout(id: pair.to)
                        }
                    }
                }
            }
            return
        }
        guard !AppConfigRegistry.isTerminal(bundleID: AppConfigRegistry.frontmostAppBundleId()) else { return }
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
                self.workQueue.async { [weak self] in
                    self?.pasteText(other)
                    DispatchQueue.main.async { [weak self] in
                        self?.isReplacingWord = false
                        self?.switchToLayout(id: pair.to)
                    }
                }
            }
        }
    }

    /// Persist a one-way mapping `word → otherLayoutEquivalent` for the pair.
    /// `pair.from` is the layout the user typed in, `pair.to` is the other.
    private func saveWordAsMapping(_ word: String, pair: LayoutPair) {
        let other = applyCharacterMapping(word, from: pair.from, to: pair.to)
        guard !other.isEmpty, other != word else {
            Log.words.debug("Remember skipped for \"\(word, privacy: .public)\" — no character mapping for \(pair.from, privacy: .public) ↔ \(pair.to, privacy: .public)")
            return
        }
        WordMapperStore.shared.set(source: word, target: other, switchLayout: false, for: pair)
        Log.words.debug("Remembered \"\(word, privacy: .public)\" → \"\(other, privacy: .public)\" for \(pair.from, privacy: .public)|\(pair.to, privacy: .public)")
    }

    /// The pair whose `from` is the current layout. If the current layout is
    /// the "to" side, returns the inverse pair. Returns nil when the current
    /// layout is neither side (e.g. a third language is active) — guessing a
    /// direction there would replace words against the wrong dictionary.
    private func currentActivePair() -> LayoutPair? {
        let settings = SettingsManager.shared
        let left = settings.leftCommandLayout
        let right = settings.rightCommandLayout
        guard !left.isEmpty, !right.isEmpty,
              left != Constants.Default.noneLanguage,
              right != Constants.Default.noneLanguage,
              !LayoutPair.namesMatch(left, right) else {
            return nil
        }
        // Use the live layout first (handles the common case of typing
        // without ever tapping the switch modifier), fall back to the cached
        // value.
        let current = currentInputSourceID() ?? currentLayoutID
        if LayoutPair.namesMatch(current, left) { return LayoutPair(from: left, to: right) }
        if LayoutPair.namesMatch(current, right) { return LayoutPair(from: right, to: left) }
        return nil
    }

    /// Stable id of the keyboard layout currently driving key events.
    ///
    /// Read from TIS on every call, so it stays correct after a language
    /// change; `currentLayoutID` is only the cached copy used when TIS is
    /// unavailable. Each read keeps `previousLayoutID` pointing at the layout
    /// the user came from.
    @discardableResult
    func currentInputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let id = KeyboardLayoutUtility.inputSourceID(of: source) else {
            return currentLayoutID.isEmpty ? nil : currentLayoutID
        }
        if !currentLayoutID.isEmpty, currentLayoutID != id {
            previousLayoutID = currentLayoutID
        }
        currentLayoutID = id
        return id
    }

    /// Localized name of the keyboard layout currently driving key events.
    /// Display only — comparisons and storage use `currentInputSourceID()`.
    func currentLayoutName() -> String? {
        guard let id = currentInputSourceID() else { return nil }
        return LayoutRegistry.displayName(forID: id)
    }

    // MARK: - Terminal input

    private func focusedElement(pid: pid_t) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid),
                                           kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func beginTerminalReplacement() -> Bool {
        guard terminalReplacementPID == nil, !isReplacingWord,
              AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              let app = NSWorkspace.shared.frontmostApplication,
              AppConfigRegistry.isTerminal(bundleID: app.bundleIdentifier) else { return false }
        terminalFocusedElement = focusedElement(pid: app.processIdentifier)
        terminalReplacementPID = app.processIdentifier
        isReplacingWord = true
        return true
    }

    private func terminalTargetIsCurrent() -> Bool {
        guard let pid = terminalReplacementPID, !IsSecureEventInputEnabled(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        if let original = terminalFocusedElement {
            guard let current = focusedElement(pid: pid), CFEqual(original, current) else { return false }
        }
        return true
    }

    private func finishTerminalReplacement(text: String? = nil, targetLayout: String? = nil) {
        let stillCurrent = terminalTargetIsCurrent()
        if stillCurrent, let targetLayout { switchToLayout(id: targetLayout) }
        wordBuffer.reset()
        if stillCurrent, let text { wordBuffer.replace(with: text) }
        let events = deferredTerminalEvents
        deferredTerminalEvents.removeAll()
        terminalReplacementPID = nil
        terminalFocusedElement = nil
        isReplacingWord = false
        leftCmd = KeyState()
        rightCmd = KeyState()
        transformKeyDown = false
        leftShiftDown = false
        rightShiftDown = false
        for (event, scalar) in events {
            if !stillCurrent || handle(type: event.type, event: event, capturedScalar: scalar) != nil {
                event.post(tap: .cgAnnotatedSessionEventTap)
            }
        }
    }

    private func transformTerminalWord(skipLayoutSwitch: Bool) {
        let original = wordBuffer.text
        guard !original.isEmpty else {
            Log.transform.debug("Terminal transform skipped: no tracked text at the cursor")
            return
        }
        guard beginTerminalReplacement() else {
            Log.transform.debug("Terminal transform skipped: input is busy, untrusted, or secure")
            return
        }
        Log.transform.debug("Terminal transform requested (characters=\(original.count, privacy: .public))")
        let shouldSwitch = !skipLayoutSwitch && SettingsManager.shared.switchLayoutAfterTransform
        TextTransformer.shared.planTypedText(original) { plan in
            guard plan.transformedText != original, TerminalInput.isSafeReplacement(plan.transformedText),
                  self.terminalTargetIsCurrent() else {
                self.finishTerminalReplacement(text: original)
                Log.transform.debug("Terminal transform skipped: unchanged text, unsafe mapping, or changed focus")
                return
            }
            self.replaceTerminalWord(original: original, replacement: plan.transformedText,
                                     targetLayout: shouldSwitch ? plan.targetLayout : nil)
        }
    }

    /// Caller has already captured and locked the terminal input on main.
    private func replaceTerminalWord(original: String, replacement: String,
                                     separatorEvent: CGEvent? = nil, targetLayout: String? = nil) {
        guard let pid = terminalReplacementPID else { return }
        workQueue.async {
            let clipboard = ClipboardManager.shared
            let saved = clipboard.saveState()
            clipboard.setString(replacement)
            let pasteCount = NSPasteboard.general.changeCount
            var didPaste = false
            defer {
                if NSPasteboard.general.changeCount == pasteCount { clipboard.restoreState(saved) }
                DispatchQueue.main.async {
                    self.finishTerminalReplacement(text: didPaste && separatorEvent == nil ? replacement : nil,
                                                   targetLayout: didPaste ? targetLayout : nil)
                }
            }

            // Let the trigger modifiers settle before posting a plain paste.
            Thread.sleep(forTimeInterval: Constants.Timing.pasteCmdVDeferSec)
            guard NSPasteboard.general.string(forType: .string) == replacement else { return }
            for _ in original {
                guard DispatchQueue.main.sync(execute: { self.terminalTargetIsCurrent() }) else { return }
                CGEventSynthesizer.press(UInt16(self.deleteKeyCode), targetPID: pid)
                usleep(Constants.Timing.backspaceDelayUs)
            }
            guard DispatchQueue.main.sync(execute: { self.terminalTargetIsCurrent() }) else { return }
            CGEventSynthesizer.press(UInt16(Constants.KeyCode.v), flags: .maskCommand, targetPID: pid)
            // shortcut: terminals do not acknowledge clipboard consumption, recheck this delay for new hosts.
            Thread.sleep(forTimeInterval: Constants.Timing.pasteRestoreDelaySec)
            didPaste = true
            if let separatorEvent,
               DispatchQueue.main.sync(execute: { self.terminalTargetIsCurrent() }) {
                // A pasted newline/tab is not Enter/completion under bracketed paste.
                separatorEvent.postToPid(pid)
            }
        }
    }

    /// Erase `originalLength` chars (since the separator key event was already
    /// suppressed), then paste `replacement + separator` via the clipboard.
    /// Runs on `workQueue`; the caller owns the `isReplacingWord` guard flag.
    private func replaceTypedWord(
        originalLength: Int,
        separator: String,
        with replacement: String
    ) {
        for _ in 0..<originalLength {
            simulateKeyDownUp(keyCode: deleteKeyCode, modifierFlags: [])
            usleep(Constants.Timing.backspaceDelayUs)
        }
        usleep(Constants.Timing.keySequenceDelayUs)
        pasteText(replacement + separator)
    }

    private func simulateKeyDownUp(keyCode: Int, modifierFlags: CGEventFlags) {
        CGEventSynthesizer.press(keyCode, flags: modifierFlags)
    }

    /// Send a Cmd+V key event to `.cgAnnotatedSessionEventTap` so it goes
    /// directly to the target app without re-entering our HID event tap.
    private func simulateCmdV() {
        CGEventSynthesizer.pressCommand(Constants.KeyCode.v)
    }

    /// Set `text` on the pasteboard, simulate Cmd+V, then restore the
    /// original pasteboard contents a moment later.
    private func pasteText(_ text: String) {
        let savedState = ClipboardManager.shared.saveState()
        ClipboardManager.shared.setString(text)
        usleep(Constants.Timing.keySequenceDelayUs)

        // If modifiers from the trigger hotkey are still held, wait so the
        // target app sees plain Cmd+V. Sleep here on workQueue — not via
        // asyncAfter on main — so the caller's isReplacingWord reset and
        // layout switch always happen after Cmd+V is sent, not before.
        let currentFlags = CGEventSource.flagsState(.combinedSessionState)
        let problematic: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        if !currentFlags.intersection(problematic).isEmpty {
            Thread.sleep(forTimeInterval: Constants.Timing.pasteCmdVDeferSec)
        }
        simulateCmdV()
        usleep(Constants.Timing.pasteSettleUs)

        // Restore after paste settles, provided the clipboard still contains
        // our text. This content check cannot detect a new copy of identical text.
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

        // Single shared implementation (see `LayoutMapperPreset.apply`):
        // direction-aware, and the reverse hop inverts with longest-match so
        // multi-character targets are not silently dropped.
        return active.apply(word, from: from)
    }

    /// Round-trip the user's current selection through the pasteboard.
    /// Saves existing pasteboard contents, simulates Cmd+C, polls for the
    /// pasteboard to change, then restores the original contents.
    ///
    /// This is the same marker-based flow `TextTransformer` uses for its
    /// Branch A / Branch B copies — both go through `ClipboardManager` so the
    /// save/restore and change-detection logic exists only once.
    /// Runs entirely off the main thread; `completion` is delivered on main.
    private func captureSelectedText(completion: @escaping (String?) -> Void) {
        workQueue.async {
            let clipboard = ClipboardManager.shared
            let savedState = clipboard.saveState()
            let (marker, markerCount) = clipboard.setMarker()

            CGEventSynthesizer.pressCommand(
                Constants.KeyCode.c,
                delayUs: Constants.Timing.captureKeyDelayUs
            )

            // Plain usleep polling inside `waitForChange` — deliberately NOT
            // `RunLoop.main.run(...)`, which re-enters the main run loop from
            // inside an event-tap callback and can reprocess queued events.
            let captured = clipboard.waitForChange(marker: marker, markerCount: markerCount)

            // Restore before handing the value back: the caller may immediately
            // re-use the pasteboard (word replacement pastes through it), and a
            // deferred restore would then race with that flow.
            clipboard.restoreState(savedState)

            DispatchQueue.main.async {
                completion(captured)
            }
        }
    }
}
