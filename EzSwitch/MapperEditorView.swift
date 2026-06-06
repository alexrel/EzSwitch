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
    @ObservedObject private var store = MapperStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var testInput: String = ""
    @State private var testOutput: String = ""
    @State private var editingKey: VisualKey? = nil
    @State private var editingModifier: KeyboardLayoutUtility.Modifier = .none
    @State private var pickerChar: String = ""
    @State private var showSaveAlert: Bool = false
    @State private var newName: String = ""

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
                    keyboardSection(title: String(localized: "No modifier (base)"), modifier: .none)
                    // Shift keys
                    keyboardSection(title: String(localized: "With Shift held"), modifier: .shift)
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
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Mapper editor"))
                    .font(.title2.bold())
                Text("\(preset.fromLayout) → \(preset.toLayout)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(verbatim: "\(preset.mapping.count) " + String(localized: "characters"))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Test Area

    private var testArea: some View {
        HStack(spacing: 10) {
            // Title
            Text(String(localized: "Test mapping"))
                .font(.headline)
                .layoutPriority(1)

            // Input field with caption above
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: String(localized: "Input (%@)"), preset.fromLayout))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextField(String(localized: "Enter text to test…"), text: $testInput)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: testInput) { _, newValue in
                        testOutput = transform(newValue)
                    }
            }
            .frame(maxWidth: .infinity)

            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .padding(.top, 14)

            // Result field with caption above
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: String(localized: "Result (%@)"), preset.toLayout))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextField("", text: .constant(testOutput))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
            }
            .frame(maxWidth: .infinity)

            // Action buttons
            HStack(spacing: 6) {
                Button {
                    applyAutoMapping()
                } label: {
                    Label(String(localized: "Auto-generate"), systemImage: "wand.and.stars")
                }
                .controlSize(.small)

                Button {
                    resetMapping()
                } label: {
                    Label(String(localized: "Clear"), systemImage: "trash")
                }
                .controlSize(.small)
            }
            .padding(.top, 14)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.05))
        )
    }
    private func keyboardSection(title: String, modifier: KeyboardLayoutUtility.Modifier) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            VStack(spacing: 3) {
                ForEach(Array(grid.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 3) {
                        ForEach(row) { key in
                            keyButton(for: key, modifier: modifier)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private func keyButton(for key: VisualKey, modifier: KeyboardLayoutUtility.Modifier) -> some View {
        let sourceChar = lookupSource(for: key, modifier: modifier)
        let targetChar = preset.mapping[sourceChar]

        return Button {
            editingKey = key
            editingModifier = modifier
        } label: {
            HStack(spacing: 3) {
                Text(sourceChar)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
                Text(targetChar ?? "—")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(targetChar != nil ? .accentColor : .secondary.opacity(0.4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(targetChar != nil ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(targetChar != nil ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Source Lookup

    /// Look up the source character for a key in the preset's source layout
    private func lookupSource(for key: VisualKey, modifier: KeyboardLayoutUtility.Modifier) -> String {
        if let char = KeyboardLayoutUtility.character(
            forKeyCode: key.keyCode,
            modifier: modifier,
            layoutName: preset.fromLayout
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
                HStack(spacing: 14) {
                    Spacer()
                    VStack(spacing: 2) {
                        Text(String(localized: "Source"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(lookupSource(for: key, modifier: editingModifier))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .frame(width: 44, height: 44)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(8)
                    }
                    Image(systemName: "arrow.right")
                        .font(.body)
                        .foregroundColor(.secondary)
                    VStack(spacing: 2) {
                        Text(String(localized: "Target"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        TextField("", text: $pickerChar)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .frame(width: 80, height: 44)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(8)
                            .help(String(localized: "Type any character, emoji or symbol"))
                    }
                    Spacer()
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
                            layoutName: preset.toLayout
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
        switch modifier {
        case .none: return String(localized: "No modifier")
        case .shift: return "Shift"
        case .option: return "Option"
        case .shiftOption: return String(localized: "Shift + Option")
        }
    }

    /// Quick suggestions for common mappings.
    /// The user-chosen modifier (from the picker) decides which two characters
    /// to suggest: the base and the variant of the OTHER modifier.
    private func suggestionsForKey(_ key: VisualKey, modifier: KeyboardLayoutUtility.Modifier) -> [String] {
        // Pair (base, shifted) when modifier is "none"/"option", (shifted, base) when it's "shift"
        let wantsShifted = (modifier == .shift || modifier == .shiftOption)
        let otherModifier: KeyboardLayoutUtility.Modifier = wantsShifted ? .none : .shift

        guard let primary = KeyboardLayoutUtility.character(
            forKeyCode: key.keyCode,
            modifier: modifier == .shiftOption ? .shift : modifier,
            layoutName: preset.toLayout
        ) else { return [] }
        guard let secondary = KeyboardLayoutUtility.character(
            forKeyCode: key.keyCode,
            modifier: otherModifier,
            layoutName: preset.toLayout
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "Extra"))
                    .font(.headline)
                Spacer()
                Button {
                    // Add a new empty extra mapping and open the picker
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

            if preset.extraMappings.isEmpty {
                Text(String(localized: "No extra mappings. Click Add to create one."))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 3) {
                    ForEach(preset.extraMappings) { mapping in
                        Button {
                            editingExtraMapping = mapping
                            isExtraPickerOpen = true
                        } label: {
                            HStack(spacing: 6) {
                                Text(mapping.source.isEmpty ? "?" : mapping.source)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .frame(minWidth: 20)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                Text(mapping.target.isEmpty ? "—" : mapping.target)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(mapping.target.isEmpty ? .secondary.opacity(0.4) : .accentColor)
                                    .lineLimit(1)
                                Spacer()
                                Text(modifierLabel(mapping.modifier))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(3)
                                // Delete button
                                Button {
                                    if let idx = preset.extraMappings.firstIndex(where: { $0.id == mapping.id }) {
                                        preset.extraMappings.remove(at: idx)
                                    }
                                    testOutput = transform(testInput)
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 11))
                                        .foregroundColor(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    // MARK: - Extra Picker Sheet

    private func extraPickerSheet(mapping: Binding<LayoutMapperPreset.ExtraMapping>) -> some View {
        VStack(spacing: 0) {
            // Top: title + modifier picker in top-right corner
            HStack(spacing: 6) {
                Text(String(localized: "Map key"))
                    .font(.headline)
                Spacer()
                // Modifier picker (segmented, in top-right)
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

                HStack(spacing: 14) {
                    Spacer()
                    VStack(spacing: 2) {
                        Text(String(localized: "Source"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        TextField("?", text: mapping.source)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .frame(width: 44, height: 44)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(8)
                    }
                    Image(systemName: "arrow.right")
                        .font(.body)
                        .foregroundColor(.secondary)
                    VStack(spacing: 2) {
                        Text(String(localized: "Target"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        TextField("", text: mapping.target)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .frame(width: 80, height: 44)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(8)
                            .help(String(localized: "Type any character, emoji or symbol"))
                    }
                    Spacer()
                }

                // Suggestions (based on source lookup if source is 1 char)
                if let sourceChar = mapping.source.wrappedValue.first,
                   let sourceKey = keyboardKeyForChar(sourceChar) {
                    let suggestions = suggestionsForKey(sourceKey, modifier: mapping.modifier.wrappedValue)
                    if !suggestions.isEmpty {
                        HStack(spacing: 2) {
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

            // Bottom: Cancel + Save
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Button {
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
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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

    /// Apply mapping to test text
    private func transform(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        let charMap = preset.characterMapping()
        // Apply base mapping first (values can be multi-character strings)
        var result = ""
        result.reserveCapacity(text.count)
        for char in text {
            if let mapped = charMap[char] {
                result.append(mapped)
            } else {
                result.append(char)
            }
        }
        // Apply extra mappings (simple substitution for any matching source char)
        for extra in preset.extraMappings {
            guard !extra.source.isEmpty, !extra.target.isEmpty else { continue }
            result = result.replacingOccurrences(of: extra.source, with: extra.target)
        }
        return result
    }
}
