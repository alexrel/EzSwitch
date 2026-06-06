import SwiftUI
import AppKit
import Carbon

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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Set Hotkey for \(actionName)"))
                .font(.system(size: 14, weight: .semibold))
            Text(String(localized: "Press a key combination. Cmd, Shift, Option, Control and a single key are required."))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(String(localized: "Hotkey"))
                    .frame(width: 80, alignment: .trailing)
                    .font(.system(size: 12))
                Text(captured?.displayLabel ?? hotkey.displayLabel)
                    .font(.system(size: 16, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor.opacity(captured == nil ? 0 : 1), lineWidth: 1.5)
                    )
                if captured != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }

            HStack {
                Button(String(localized: "Clear")) {
                    hotkey = .none
                    captured = Hotkey.none
                }
                .controlSize(.small)
                Spacer()
                Button(String(localized: "Cancel"), action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save")) {
                    if let c = captured { hotkey = c }
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(captured == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
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
