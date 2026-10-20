import SwiftUI

// MARK: - Visual Keyboard Layout Definition

/// Defines the visual layout of a QWERTY keyboard for the editor.
/// Each row contains key codes that are used to display
/// source and target characters.
struct VisualKey: Identifiable, Hashable {
    let id: String
    /// Virtual key code (used for display in UI; not for lookup)
    let keyCode: UInt16
}

struct KeyboardLayoutGrid {
    /// All rows of the keyboard
    let rows: [[VisualKey]]

    /// Standard US QWERTY layout
    static let standard: KeyboardLayoutGrid = {
        // Row 1: digits + top symbols
        // Includes §/± (0x0A) and backtick/` (0x32)
        let row1: [VisualKey] = [
            VisualKey(id: "backtick", keyCode: 0x32),
            VisualKey(id: "section", keyCode: 0x0A),
            VisualKey(id: "1", keyCode: 0x12),
            VisualKey(id: "2", keyCode: 0x13),
            VisualKey(id: "3", keyCode: 0x14),
            VisualKey(id: "4", keyCode: 0x15),
            VisualKey(id: "5", keyCode: 0x16),
            VisualKey(id: "6", keyCode: 0x17),
            VisualKey(id: "7", keyCode: 0x1C),
            VisualKey(id: "8", keyCode: 0x19),
            VisualKey(id: "9", keyCode: 0x1A),
            VisualKey(id: "0", keyCode: 0x1D),
            VisualKey(id: "minus", keyCode: 0x1B),
            VisualKey(id: "equal", keyCode: 0x18),
        ]

        // Row 2: qwerty
        let row2: [VisualKey] = [
            VisualKey(id: "q", keyCode: 0x0C),
            VisualKey(id: "w", keyCode: 0x0D),
            VisualKey(id: "e", keyCode: 0x0E),
            VisualKey(id: "r", keyCode: 0x0F),
            VisualKey(id: "t", keyCode: 0x11),
            VisualKey(id: "y", keyCode: 0x10),
            VisualKey(id: "u", keyCode: 0x20),
            VisualKey(id: "i", keyCode: 0x22),
            VisualKey(id: "o", keyCode: 0x1F),
            VisualKey(id: "p", keyCode: 0x23),
            VisualKey(id: "lbracket", keyCode: 0x21),
            VisualKey(id: "rbracket", keyCode: 0x1E),
            VisualKey(id: "backslash", keyCode: 0x2A),
        ]

        // Row 3: asdf
        let row3: [VisualKey] = [
            VisualKey(id: "a", keyCode: 0x00),
            VisualKey(id: "s", keyCode: 0x01),
            VisualKey(id: "d", keyCode: 0x02),
            VisualKey(id: "f", keyCode: 0x03),
            VisualKey(id: "g", keyCode: 0x05),
            VisualKey(id: "h", keyCode: 0x04),
            VisualKey(id: "j", keyCode: 0x26),
            VisualKey(id: "k", keyCode: 0x28),
            VisualKey(id: "l", keyCode: 0x25),
            VisualKey(id: "semicolon", keyCode: 0x29),
            VisualKey(id: "quote", keyCode: 0x27),
        ]

        // Row 4: zxcv
        let row4: [VisualKey] = [
            VisualKey(id: "z", keyCode: 0x06),
            VisualKey(id: "x", keyCode: 0x07),
            VisualKey(id: "c", keyCode: UInt16(Constants.KeyCode.c)),
            VisualKey(id: "v", keyCode: UInt16(Constants.KeyCode.v)),
            VisualKey(id: "b", keyCode: 0x0B),
            VisualKey(id: "n", keyCode: 0x2D),
            VisualKey(id: "m", keyCode: 0x2E),
            VisualKey(id: "comma", keyCode: 0x2B),
            VisualKey(id: "period", keyCode: 0x2F),
            VisualKey(id: "slash", keyCode: 0x2C),
        ]

        return KeyboardLayoutGrid(rows: [row1, row2, row3, row4])
    }()
}

// MARK: - Editor View

/// Visual editor for a `LayoutMapperPreset`.
/// Shows a virtual keyboard where each key displays its mapping.
struct MapperEditorView: View {
    @Binding var preset: LayoutMapperPreset
    var presetsForPair: [LayoutMapperPreset] = []
    var onSelectPreset: ((String) -> Void)? = nil
    var onNewPreset: (() -> Void)? = nil
    var onDeletePreset: (() -> Void)? = nil

    @ObservedObject private var store = MapperStore.shared

    @State private var testInput: String = ""
    @State private var testOutput: String = ""
    @State private var editingKey: VisualKey? = nil
    @State private var editingModifier: KeyboardLayoutUtility.Modifier = .none
    @State private var pickerChar: String = ""
    @State private var showSaveAlert: Bool = false
    @State private var newName: String = ""
    @State private var showAutoConfirm: Bool = false
    @State private var showClearKeysConfirm: Bool = false

    // Local working copy of the modifier for the picker so the user can override
    // the auto-detected one (e.g. map "п" with Shift modifier).
    @State private var pickerModifier: KeyboardLayoutUtility.Modifier = .none
    @State private var lastEditingKey: VisualKey? = nil

    // Extra mappings (custom key combos with explicit modifier)
    @State private var editingExtraMapping: LayoutMapperPreset.ExtraMapping? = nil
    @State private var isExtraPickerOpen: Bool = false

    private let grid = KeyboardLayoutGrid.standard

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 16) {
                    // Test area
                    testArea
                    // Normal keys
                    keyboardSection(
                        title: String(localized: "No modifier (base)"),
                        icon: "keyboard",
                        modifier: .none
                    )
                    // Shift keys
                    keyboardSection(
                        title: String(localized: "With Shift held"),
                        icon: "shift.fill",
                        modifier: .shift
                    )
                    // Extra mappings (custom combos with explicit modifier)
                    extraSection
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: Binding(
            get: { editingKey != nil },
            set: { if !$0 { editingKey = nil } }
        )) {
            if let key = editingKey {
                charPickerSheet(for: key)
            }
        }
        .sheet(isPresented: $isExtraPickerOpen) {
            if let mapping = editingExtraMapping {
                extraPickerSheet(mapping: binding(for: mapping))
            }
        }
        .confirmationDialog(
            String(localized: "Overwrite current mapping with auto-generated keys?"),
            isPresented: $showAutoConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Auto-generate"), role: .destructive) {
                applyAutoMapping()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "All custom key changes in “\(preset.name)” will be replaced with the default \(preset.displayFromLayout) → \(preset.displayToLayout) layout mapping."))
        }
        .confirmationDialog(
            String(localized: "Clear all mapped keys in this preset?"),
            isPresented: $showClearKeysConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Clear keys"), role: .destructive) {
                resetMapping()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This will clear all \(preset.mapping.count) mapped keys in “\(preset.name)”."))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(String(localized: "Mapper editor"))
                        .font(.title3.bold())
                    Text(verbatim: "\(preset.mapping.count) " + String(localized: "characters"))
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.12))
                        )
                }
                Text("\(preset.displayFromLayout) ↔ \(preset.displayToLayout)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .fixedSize(horizontal: true, vertical: true)

            Spacer()

            // Preset selector & preset actions (only visible on Character Mappings tab)
            HStack(spacing: 6) {
                if !presetsForPair.isEmpty {
                    Picker("", selection: Binding(
                        get: { preset.id },
                        set: { newID in
                            onSelectPreset?(newID)
                        }
                    )) {
                        ForEach(presetsForPair) { p in
                            Text(p.name).tag(p.id)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: 220)
                }

                if let onNewPreset = onNewPreset {
                    Button {
                        onNewPreset()
                    } label: {
                        Label(String(localized: "New"), systemImage: "plus")
                    }
                    .controlSize(.small)
                    .fixedSize()
                    .help(String(localized: "Create a new preset"))
                }

                Button {
                    if preset.mapping.isEmpty {
                        applyAutoMapping()
                    } else {
                        showAutoConfirm = true
                    }
                } label: {
                    Label(String(localized: "Auto"), systemImage: "wand.and.stars")
                }
                .controlSize(.small)
                .fixedSize()
                .help(String(localized: "Fill keys automatically from system layouts"))

                Button {
                    showClearKeysConfirm = true
                } label: {
                    Image(systemName: "eraser")
                }
                .controlSize(.small)
                .disabled(preset.mapping.isEmpty)
                .help(String(localized: "Clear all keys…"))

                if let onDeletePreset = onDeletePreset {
                    Button(role: .destructive) {
                        onDeletePreset()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .controlSize(.small)
                    .help(String(localized: "Delete preset…"))
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    // MARK: - Test Area

    private var testArea: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text(String(localized: "Test mapping"))
                    .font(.subheadline.weight(.semibold))
            }
            .layoutPriority(1)

            // Input field
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: String(localized: "Input (%@)"), preset.displayFromLayout))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    TextField(String(localized: "Enter text to test…"), text: $testInput)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: testInput) { _, newValue in
                            testOutput = transform(newValue)
                        }
                    if !testInput.isEmpty {
                        Button {
                            testInput = ""
                            testOutput = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Clear test text"))
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.top, 14)

            // Result field
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: String(localized: "Result (%@)"), preset.displayToLayout))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextField("", text: .constant(testOutput))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Keyboard Section

    private func keyboardSection(title: String, icon: String, modifier: KeyboardLayoutUtility.Modifier) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 4) {
                    Text(preset.displayFromLayout)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Image(systemName: "arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(preset.displayToLayout)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.accentColor)
                    Text("·")
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(String(localized: "Click any key to edit"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)

            // Recessed aluminum-style keyboard well
            VStack(spacing: 6) {
                ForEach(Array(grid.rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 6) {
                        // Left decorative modifier cap to create authentic staggered keyboard geometry
                        if rowIndex == 1 {
                            decorativeCap(symbol: "arrow.right.to.line.compact", fallbackLabel: "tab", width: 38)
                        } else if rowIndex == 2 {
                            decorativeCap(symbol: "capslock", fallbackLabel: "caps", width: 46)
                        } else if rowIndex == 3 {
                            decorativeCap(symbol: "shift.fill", fallbackLabel: "shift", width: 58, isHighlighted: modifier == .shift)
                        }

                        ForEach(row) { key in
                            keyButton(for: key, modifier: modifier)
                        }

                        // Right decorative cap to balance the row widths
                        if rowIndex == 2 {
                            decorativeCap(symbol: "return", fallbackLabel: "return", width: 46)
                        } else if rowIndex == 3 {
                            decorativeCap(symbol: "shift.fill", fallbackLabel: "shift", width: 58, isHighlighted: modifier == .shift)
                        }
                    }
                }
            }
            // A physical keyboard is always laid out left-to-right, even in RTL locales.
            .environment(\.layoutDirection, .leftToRight)
            .padding(11)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.08),
                                    Color.black.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                }
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func decorativeCap(symbol: String, fallbackLabel: String, width: CGFloat, isHighlighted: Bool = false) -> some View {
        ZStack {
            // 3D bottom lip
            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                .fill(
                    isHighlighted
                        ? Color.accentColor.opacity(0.38)
                        : Color.black.opacity(0.18)
                )
                .offset(y: 2)

            // Keycap top surface
            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isHighlighted
                            ? [Color.accentColor.opacity(0.24), Color.accentColor.opacity(0.14)]
                            : [Color.primary.opacity(0.05), Color.primary.opacity(0.09)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .background(
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(Color(NSColor.windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .stroke(
                            isHighlighted
                                ? Color.accentColor.opacity(0.55)
                                : Color.primary.opacity(0.12),
                            lineWidth: 1
                        )
                )

            // Modifier legend + optional LED indicator dot (like Apple Caps/Shift LED)
            ZStack {
                if isHighlighted {
                    VStack {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 4.5, height: 4.5)
                                .shadow(color: Color.green.opacity(0.8), radius: 2)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(5)
                }

                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isHighlighted ? .accentColor : .secondary.opacity(0.65))
            }
        }
        .frame(width: width, height: 40)
    }

    private func keyButton(for key: VisualKey, modifier: KeyboardLayoutUtility.Modifier) -> some View {
        let sourceChar = lookupSource(for: key, modifier: modifier)
        let targetChar = preset.mapping[sourceChar]

        return KeycapButton(
            sourceChar: sourceChar,
            targetChar: targetChar,
            action: {
                editingKey = key
                editingModifier = modifier
            }
        )
    }

    // MARK: - Source Lookup

    /// Look up the source character for a key in the preset's source layout
    private func lookupSource(for key: VisualKey, modifier: KeyboardLayoutUtility.Modifier) -> String {
        if let char = KeyboardLayoutUtility.character(
            forKeyCode: key.keyCode,
            modifier: modifier,
            layout: preset.fromLayout
        ) {
            return String(char)
        }
        return "?"
    }

    /// Look up the current target character (for the same key/modifier)
    private func lookupCurrentTarget(for key: VisualKey, modifier: KeyboardLayoutUtility.Modifier) -> String? {
        let sourceChar = lookupSource(for: key, modifier: modifier)
        return preset.mapping[sourceChar]
    }

    // MARK: - Picker Sheet

    private func charPickerSheet(for key: VisualKey) -> some View {
        VStack(spacing: 0) {
            // Top: title (no buttons, hugs the top edge)
            HStack(spacing: 6) {
                Text(String(localized: "Map key"))
                    .font(.headline)
                Text(modifierLabel(editingModifier))
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(4)
                Spacer()
            }
            .padding(.top, 2)

            // Middle: Source -> Target + Suggestions (occupies remaining space)
            VStack(spacing: 8) {
                Spacer(minLength: 0)

                // Source → Target row, centered horizontally
                VStack(spacing: 4) {
                    HStack(spacing: 14) {
                        Spacer()
                        Text(String(localized: "Source"))
                            .frame(width: 44)
                        Color.clear
                            .frame(width: 16, height: 1)
                        Text(String(localized: "Target"))
                            .frame(width: 80)
                        Spacer()
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)

                    HStack(spacing: 14) {
                        Spacer()
                        Text(lookupSource(for: key, modifier: editingModifier))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                            )

                        Image(systemName: "arrow.right")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 16)

                        TextField("", text: $pickerChar)
                            .textFieldStyle(.plain)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .frame(width: 80, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1.5)
                            )
                            .help(String(localized: "Type any character, emoji or symbol"))

                        Spacer()
                    }
                }

                // Suggestions with label
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Suggestions"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    let suggestions = suggestionsForKey(key, modifier: editingModifier)
                    if !suggestions.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(suggestions, id: \.self) { s in
                                Button {
                                    pickerChar = s
                                } label: {
                                    Text(s)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .frame(minWidth: 22)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            // Bottom: action buttons pushed to the corners
            HStack {
                HStack(spacing: 6) {
                    Button {
                        pickerChar = ""
                    } label: {
                        Label(String(localized: "Clear"), systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                    .help(String(localized: "Remove mapping for this key"))

                    Button {
                        // Auto-fill from target layout for the current selected modifier
                        if let auto = KeyboardLayoutUtility.character(
                            forKeyCode: key.keyCode,
                            modifier: pickerModifier,
                            layout: preset.toLayout
                        ) {
                            pickerChar = String(auto)
                        }
                    } label: {
                        Label(String(localized: "Auto"), systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(String(localized: "Auto-fill from target layout"))
                }

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        editingKey = nil
                    } label: {
                        Label(String(localized: "Cancel"), systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)

                    Button {
                        applyPickerSelection()
                        editingKey = nil
                    } label: {
                        Label(String(localized: "Save"), systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.return)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: 400, height: 220)
        .onAppear {
            // Initialise the working state from the key the user clicked
            if lastEditingKey != key {
                lastEditingKey = key
                pickerModifier = editingModifier
            }
            pickerChar = lookupCurrentTarget(for: key, modifier: pickerModifier) ?? ""
        }
    }

    /// Human-readable label for the current modifier context
    private func modifierLabel(_ modifier: KeyboardLayoutUtility.Modifier) -> String {
        modifier.displayName
    }

    /// Quick suggestions for common mappings.
    /// Suggest the selected target variant plus a base/Shift alternative.
    /// Shift+Option uses Shift as the primary suggestion.
    private func suggestionsForKey(_ key: VisualKey, modifier: KeyboardLayoutUtility.Modifier) -> [String] {
        // Offer base when Shift is selected; otherwise offer Shift.
        let wantsShifted = (modifier == .shift || modifier == .shiftOption)
        let otherModifier: KeyboardLayoutUtility.Modifier = wantsShifted ? .none : .shift

        guard let primary = KeyboardLayoutUtility.character(
            forKeyCode: key.keyCode,
            modifier: modifier == .shiftOption ? .shift : modifier,
            layout: preset.toLayout
        ) else { return [] }
        guard let secondary = KeyboardLayoutUtility.character(
            forKeyCode: key.keyCode,
            modifier: otherModifier,
            layout: preset.toLayout
        ) else { return [] }
        return [String(primary), String(secondary)]
    }

    // MARK: - Actions

    private func applyPickerSelection() {
        guard let key = editingKey else { return }
        // Use the user-chosen modifier from the picker (defaulting to the
        // modifier context the key was clicked in)
        let modifier = pickerModifier
        let sourceChar = lookupSource(for: key, modifier: modifier)
        if pickerChar.isEmpty {
            preset.mapping.removeValue(forKey: sourceChar)
        } else {
            // Allow any custom character (including multi-byte / emoji) — the
            // TextField already accepts arbitrary Unicode input.
            preset.mapping[sourceChar] = pickerChar
        }
        // Recompute test output
        testOutput = transform(testInput)
    }

    private func applyAutoMapping() {
        let mapping = KeyboardLayoutUtility.buildMapping(
            fromLayout: preset.fromLayout,
            toLayout: preset.toLayout
        )
        preset.mapping = mapping
        preset.updatedAt = Date()
        testOutput = transform(testInput)
    }

    private func resetMapping() {
        preset.mapping = [:]
        testOutput = testInput
    }

    // MARK: - Extra Mappings Section

    private var extraSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "plus.forwardslash.minus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text(String(localized: "Extra"))
                    .font(.subheadline.weight(.semibold))
                if !preset.extraMappings.isEmpty {
                    Text("\(preset.extraMappings.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.12))
                        )
                }
                Spacer()
                Button {
                    let newMapping = LayoutMapperPreset.ExtraMapping(
                        source: "",
                        target: "",
                        modifier: .none
                    )
                    preset.extraMappings.append(newMapping)
                    editingExtraMapping = newMapping
                    isExtraPickerOpen = true
                } label: {
                    Label(String(localized: "Add"), systemImage: "plus")
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 4)

            if preset.extraMappings.isEmpty {
                HStack {
                    Spacer()
                    Text(String(localized: "No extra mappings. Click Add to create one."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 10)
                    Spacer()
                }
            } else {
                VStack(spacing: 4) {
                    ForEach(preset.extraMappings) { mapping in
                        let hasReverse = preset.extraMappings.contains {
                            !mapping.source.isEmpty && !mapping.target.isEmpty &&
                            $0.source == mapping.target && $0.target == mapping.source
                        }
                        MappingListRow(
                            source: mapping.source.isEmpty ? "?" : mapping.source,
                            target: mapping.target.isEmpty ? "—" : mapping.target,
                            modifier: mapping.modifier,
                            isBidirectional: hasReverse,
                            onEdit: {
                                editingExtraMapping = mapping
                                isExtraPickerOpen = true
                            },
                            onDelete: {
                                if let idx = preset.extraMappings.firstIndex(where: { $0.id == mapping.id }) {
                                    preset.extraMappings.remove(at: idx)
                                }
                                testOutput = transform(testInput)
                            }
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Extra Picker Sheet

    private func extraPickerSheet(mapping: Binding<LayoutMapperPreset.ExtraMapping>) -> some View {
        VStack(spacing: 0) {
            // Top: title + modifier picker in top-right corner
            HStack(spacing: 6) {
                Text(String(localized: "Extra Mapping"))
                    .font(.headline)
                Spacer()
                Picker("", selection: mapping.modifier) {
                    Text(String(localized: "None")).tag(KeyboardLayoutUtility.Modifier.none)
                    Text("Shift").tag(KeyboardLayoutUtility.Modifier.shift)
                    Text("Option").tag(KeyboardLayoutUtility.Modifier.option)
                    Text("Shift+Opt").tag(KeyboardLayoutUtility.Modifier.shiftOption)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.mini)
                .frame(width: 200)
                .help(String(localized: "Choose which modifier triggers this mapping"))
            }
            .padding(.top, 2)

            // Middle: Source → Target + Suggestions
            VStack(spacing: 8) {
                Spacer(minLength: 0)

                VStack(spacing: 4) {
                    HStack(spacing: 14) {
                        Spacer()
                        Text(String(localized: "Source"))
                            .frame(width: 90)
                        Color.clear
                            .frame(width: 16, height: 1)
                        Text(String(localized: "Target"))
                            .frame(width: 110)
                        Spacer()
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)

                    HStack(spacing: 14) {
                        Spacer()
                        TextField("?", text: mapping.source)
                            .textFieldStyle(.plain)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .frame(width: 90, height: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1.5)
                            )
                            .onChange(of: mapping.source.wrappedValue) { _, newValue in
                                if newValue.contains(where: { $0.isUppercase }) && mapping.modifier.wrappedValue == .none {
                                    mapping.modifier.wrappedValue = .shift
                                }
                            }

                        Image(systemName: "arrow.right")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 16)

                        TextField("", text: mapping.target)
                            .textFieldStyle(.plain)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .frame(width: 110, height: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1.5)
                            )
                            .help(String(localized: "Type any character, emoji or symbol"))

                        Spacer()
                    }
                }

                // Suggestions (based on source lookup if source is 1 char)
                if let sourceChar = mapping.source.wrappedValue.first,
                   let sourceKey = keyboardKeyForChar(sourceChar) {
                    let suggestions = suggestionsForKey(sourceKey, modifier: mapping.modifier.wrappedValue)
                    if !suggestions.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(suggestions, id: \.self) { s in
                                Button {
                                    mapping.target.wrappedValue = s
                                } label: {
                                    Text(s)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .frame(minWidth: 22)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            // Bottom: Clear + Cancel + Save
            HStack {
                Button {
                    mapping.source.wrappedValue = ""
                    mapping.target.wrappedValue = ""
                } label: {
                    Label(String(localized: "Clear"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)

                Spacer()
                HStack(spacing: 6) {
                    Button {
                        // Remove empty placeholder if user cancelled adding a new extra mapping
                        if mapping.source.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty &&
                           mapping.target.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty {
                            let id = mapping.id
                            preset.extraMappings.removeAll { $0.id == id }
                        }
                        isExtraPickerOpen = false
                    } label: {
                        Label(String(localized: "Cancel"), systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)

                    Button {
                        isExtraPickerOpen = false
                        testOutput = transform(testInput)
                    } label: {
                        Label(String(localized: "Save"), systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.return)
                    .disabled(mapping.source.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty ||
                              mapping.target.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 400, height: 220)
    }

    /// Try to find the VisualKey that produces the given character in the source layout.
    private func keyboardKeyForChar(_ char: Character) -> VisualKey? {
        for row in grid.rows {
            for key in row {
                if lookupSource(for: key, modifier: .none) == String(char) {
                    return key
                }
            }
        }
        return nil
    }

    /// Helper to get a Binding for an ExtraMapping inside the preset array
    private func binding(for mapping: LayoutMapperPreset.ExtraMapping) -> Binding<LayoutMapperPreset.ExtraMapping> {
        guard let index = preset.extraMappings.firstIndex(where: { $0.id == mapping.id }) else {
            // Return a dummy binding — should never happen
            return .constant(mapping)
        }
        return $preset.extraMappings[index]
    }

    /// Apply mapping to test text (auto-detects forward vs reverse direction)
    private func transform(_ text: String) -> String {
        preset.transform(text)
    }
}

// MARK: - Tactile Keycap Button

private struct KeycapButton: View {
    let sourceChar: String
    let targetChar: String?
    let action: () -> Void

    @State private var isHovered: Bool = false

    private var isMapped: Bool {
        if let targetChar = targetChar, !targetChar.isEmpty {
            return true
        }
        return false
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Top-left legend: source character (like secondary language on Apple keycaps)
                VStack {
                    HStack {
                        Text(sourceChar)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(isHovered ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
                .padding(.leading, 6)

                // Subtle diagonal cue in center
                Image(systemName: "arrow.down.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(
                        isHovered
                            ? Color.accentColor.opacity(0.75)
                            : Color.secondary.opacity(isMapped ? 0.25 : 0.12)
                    )

                // Bottom-right legend: mapped target character
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        Text(targetChar ?? "—")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(
                                isMapped
                                    ? .accentColor
                                    : Color.secondary.opacity(0.35)
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .padding(.bottom, 3.5)
                .padding(.trailing, 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                ZStack {
                    // Bottom 3D keycap skirt / bevel
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(
                            isHovered
                                ? Color.accentColor.opacity(0.38)
                                : Color.black.opacity(isMapped ? 0.18 : 0.10)
                        )
                        .offset(y: 2)

                    // Base window color backing
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(Color(NSColor.windowBackgroundColor).opacity(isMapped ? 1.0 : 0.55))

                    // Subtle top-to-bottom keycap surface gradient
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isHovered
                                    ? [Color.accentColor.opacity(0.14), Color.accentColor.opacity(0.06)]
                                    : [Color.white.opacity(0.65), Color.black.opacity(0.025)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Crisp keycap border
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .stroke(
                            isHovered
                                ? Color.accentColor.opacity(0.85)
                                : Color.primary.opacity(isMapped ? 0.14 : 0.07),
                            lineWidth: isHovered ? 1.5 : 0.8
                        )
                }
            )
            .offset(y: isHovered ? -0.5 : 0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Unified Mapping Row (used in both Extra and Word Substitutions)

struct MappingListRow: View {
    let source: String
    let target: String
    var modifier: KeyboardLayoutUtility.Modifier? = nil
    var isBidirectional: Bool = false
    var switchLayout: Bool = false
    var sourceWidth: CGFloat? = nil
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Clickable main area (opens Edit sheet)
            Button(action: onEdit) {
                HStack(spacing: 8) {
                    Group {
                        if let width = sourceWidth {
                            Text(source)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                                .frame(minWidth: width, alignment: .leading)
                                .lineLimit(1)
                        } else {
                            Text(source)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                    }

                    Image(systemName: isBidirectional ? "arrow.left.and.right" : "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isBidirectional ? .accentColor : .secondary)
                        .frame(width: 16)

                    Text(target)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentColor)
                        .lineLimit(1)

                    Spacer()

                    if switchLayout {
                        HStack(spacing: 3) {
                            Image(systemName: "globe")
                                .font(.system(size: 8, weight: .bold))
                            Text(String(localized: "Switch layout"))
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundColor(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.purple.opacity(0.12))
                        )
                    }

                    if isBidirectional {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 8, weight: .bold))
                            Text(String(localized: "Both ways"))
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                    }

                    if let modifier = modifier {
                        Text(modifier.displayName)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(modifier == .none ? .secondary : .accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(modifier == .none ? Color.secondary.opacity(0.12) : Color.accentColor.opacity(0.14))
                            )
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isHovered ? .red.opacity(0.85) : .secondary.opacity(0.65))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.red.opacity(isHovered ? 0.08 : 0))
                    )
            }
            .buttonStyle(.plain)
            .help(String(localized: "Delete"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isHovered
                        ? Color.accentColor.opacity(0.10)
                        : Color(NSColor.windowBackgroundColor).opacity(0.85)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isHovered
                        ? Color.accentColor.opacity(0.45)
                        : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
