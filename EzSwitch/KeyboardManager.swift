import Cocoa
import Carbon

final class KeyboardManager {
    static let shared = KeyboardManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var _isMonitoring = false
    private var _suppressEvents = false

    private let doubleTapThreshold: TimeInterval = 0.25
    private let commandMaxHold: TimeInterval = 0.35

    // Key codes
    private let leftShiftKeyCode: Int = 56
    private let rightShiftKeyCode: Int = 60
    private let leftOptionKeyCode: Int = 58
    private let rightOptionKeyCode: Int = 61
    private let leftCmdKeyCode: Int = 55
    private let rightCmdKeyCode: Int = 54

    private struct KeyState {
        var isDown = false
        var downAt: TimeInterval = 0
        var cancelled = false
    }

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

        // 1) Any regular key during Cmd -> cancel
        if type == .keyDown {
            if leftCmd.isDown { leftCmd.cancelled = true }
            if rightCmd.isDown { rightCmd.cancelled = true }
            if transformKeyDown { transformKeyCancelled = true }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            // 2) Modifiers during Cmd -> cancel (Shift/Alt/Ctrl/Fn)
            let forbidden: CGEventFlags = [.maskShift, .maskAlternate, .maskControl, .maskSecondaryFn]
            if leftCmd.isDown || rightCmd.isDown {
                if !flags.intersection(forbidden).isEmpty {
                    if leftCmd.isDown { leftCmd.cancelled = true }
                    if rightCmd.isDown { rightCmd.cancelled = true }
                }
            }

            // 3) CMD logic
            if keyCode == leftCmdKeyCode {
                updateCmd(&leftCmd, isDown: flags.contains(.maskCommand), now: now, lang: SettingsManager.shared.leftCommandLanguage)
            } else if keyCode == rightCmdKeyCode {
                updateCmd(&rightCmd, isDown: flags.contains(.maskCommand), now: now, lang: SettingsManager.shared.rightCommandLanguage)
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
                switchToLayout(named: lang)
            }
            state.isDown = false
        }
    }

    func switchToLayout(named: String) {
        if named == "None" { return }

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
}
