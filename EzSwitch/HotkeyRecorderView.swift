import SwiftUI
import AppKit
import Carbon

/// Visual representation of hotkey tokens as physical-style keyboard keycaps.
struct KeycapsView: View {
    let tokens: [String]
    var scale: KeycapScale = .regular

    enum KeycapScale {
        case small    // For compact lists and inline labels (e.g. Settings card)
        case regular  // For buttons and toolbars (e.g. WordSubstitution toolbar)
        case large    // For hero presentation (e.g. Hotkey recorder sheet)
    }

    @Environment(\.colorScheme) private var colorScheme

    private var fontSize: CGFloat {
        switch scale {
        case .small: return 10
        case .regular: return 11
        case .large: return 15
        }
    }

    private var minWidth: CGFloat {
        switch scale {
        case .small: return 15
        case .regular: return 19
        case .large: return 28
        }
    }

    private var minHeight: CGFloat {
        switch scale {
        case .small: return 14
        case .regular: return 18
        case .large: return 28
        }
    }

    private var cornerRadius: CGFloat {
        switch scale {
        case .small: return 3.5
        case .regular: return 4.5
        case .large: return 6.5
        }
    }

    private var hPadding: CGFloat {
        switch scale {
        case .small: return 3
        case .regular: return 5
        case .large: return 8
        }
    }

    var body: some View {
        HStack(spacing: scale == .large ? 4 : 2.5) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                Text(token)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.88))
                    .frame(minWidth: minWidth, minHeight: minHeight)
                    .padding(.horizontal, hPadding)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.2)
                                    : Color.black.opacity(0.18),
                                lineWidth: scale == .large ? 0.8 : 0.5
                            )
                    )
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.08),
                        radius: scale == .large ? 1.5 : 0.6,
                        y: scale == .large ? 1 : 0.5
                    )
            }
        }
    }
}

/// Modal sheet for assigning a keyboard shortcut to an action.
///
/// Uses a local NSEvent monitor (so the global CGEvent tap in
/// `KeyboardManager` is bypassed while the recorder has focus) to
/// capture the next key combination the user presses.
struct HotkeyRecorderView: View {
    @Binding var hotkey: Hotkey
    let actionName: String
    let onClose: () -> Void

    @State private var captured: Hotkey? = nil
    @State private var monitor: Any? = nil

    private var activeHotkey: Hotkey {
        captured ?? hotkey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Set Hotkey for \(actionName)"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(String(localized: "Press a key combination. Cmd, Shift, Option, Control and a single key are required."))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Hero hotkey presentation using realistic keycaps
            HStack(spacing: 12) {
                Text(String(localized: "Hotkey"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)

                HStack(spacing: 8) {
                    KeycapsView(tokens: activeHotkey.displayTokens, scale: .large)

                    if captured != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 16))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(
                            captured != nil
                                ? Color.accentColor.opacity(0.7)
                                : Color.primary.opacity(0.08),
                            lineWidth: captured != nil ? 1.5 : 1
                        )
                )

                Spacer()
            }

            // Modern bordered actions
            HStack(spacing: 8) {
                Button {
                    hotkey = .none
                    captured = Hotkey.none
                } label: {
                    Label(String(localized: "Clear"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)

                Spacer()

                Button(action: onClose) {
                    Label(String(localized: "Cancel"), systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)

                Button {
                    if let c = captured { hotkey = c }
                    onClose()
                } label: {
                    Label(String(localized: "Save"), systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .disabled(captured == nil)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { installMonitor() }
        .onDisappear { removeMonitor() }
    }

    // MARK: - Local event monitor

    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc → cancel
            if event.keyCode == UInt16(kVK_Escape) {
                onClose()
                return nil
            }
            // Ignore lone modifier presses
            if isModifierKey(event.keyCode) { return event }
            // Require at least one modifier
            let mods = event.modifierFlags
            guard mods.contains(.command)
                  || mods.contains(.shift)
                  || mods.contains(.option)
                  || mods.contains(.control) else {
                return event
            }
            captured = Hotkey(keyCode: event.keyCode,
                               modifiers: carbonModifiers(from: mods))
            return nil // Consume
        }
    }

    private func removeMonitor() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func isModifierKey(_ keyCode: UInt16) -> Bool {
        let modifierCodes: Set<UInt16> = [
            UInt16(kVK_Command), UInt16(kVK_Shift), UInt16(kVK_Option),
            UInt16(kVK_Control)
        ]
        let rightModifierCodes: Set<UInt16> = [
            UInt16(kVK_RightCommand), UInt16(kVK_RightShift),
            UInt16(kVK_RightOption), UInt16(kVK_RightControl)
        ]
        let functionCodes: Set<UInt16> = [UInt16(kVK_Function)]
        return modifierCodes.contains(keyCode)
            || rightModifierCodes.contains(keyCode)
            || functionCodes.contains(keyCode)
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command)  { m |= Constants.ModifierMask.command }
        if flags.contains(.shift)    { m |= Constants.ModifierMask.shift }
        if flags.contains(.option)   { m |= Constants.ModifierMask.option }
        if flags.contains(.control)  { m |= Constants.ModifierMask.control }
        return m
    }
}
