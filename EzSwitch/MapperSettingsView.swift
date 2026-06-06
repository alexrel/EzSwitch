import SwiftUI

/// All-in-one mapper window: pick a layout pair + preset, then edit the
/// mapping on a virtual keyboard. Replaces the previous two-step
/// (preset list → editor) flow with a single, compact screen.
struct MapperSettingsView: View {
    @ObservedObject private var store = MapperStore.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var fromLayout: String = ""
    @State private var toLayout: String = ""
    @State private var availableLayouts: [String] = []

    /// The preset being edited. `nil` means we are about to create a new one
    /// (after the user picks a pair and clicks "New" or "Auto").
    @State private var working: LayoutMapperPreset? = nil
    @State private var showNewSheet: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var mode: EditorMode = .character

    private enum EditorMode: String, CaseIterable, Identifiable {
        case character = "Character Mappings"
        case word = "Word Substitutions"
        var id: String { rawValue }
    }

    private let noneOption = "None"

    var body: some View {
        VStack(spacing: 0) {
            // Top section: pair picker + segmented mode switcher.
            // Pinned to a fixed height so the From/To block and the
            // segmented control don't shift when switching between
            // tabs (each tab's content has a different intrinsic height).
            VStack(spacing: 0) {
                // 1) Pair + preset selector
                header
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                Divider()

                // 1b) Mode switcher (character vs word-level)
                Picker("", selection: $mode) {
                    ForEach(EditorMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                Divider()
            }

            // 2) Editor (visual keyboard + test area + picker) or word list.
            // The Group with .frame(maxHeight: .infinity) gives the bottom
            // content (Table, ScrollView, etc.) a concrete height to render
            // into. The top section above is pinned at 112pt, so the
            // window height change between tabs is absorbed by this Group
            // — the From/To block and the segmented Picker stay put.
            Group {
                switch mode {
                case .character:
                    if let _ = working {
                        WorkingEditor(
                            working: $working,
                            onSave: { store.save($0) },
                            onDelete: { id in
                                store.delete(id: id)
                                working = selectPresetForCurrentPair()
                            }
                        )
                    } else {
                        emptyState
                    }
                case .word:
                    WordSubstitutionView()
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 540)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            reloadLayouts()
            if fromLayout.isEmpty { fromLayout = "Russian – PC" }
            if toLayout.isEmpty { toLayout = "ABC" }
            // Auto-load the preset the user has selected for this pair
            // (falling back to the first preset if nothing is saved).
            working = selectPresetForCurrentPair()
        }
        .onChange(of: fromLayout) { _, _ in
            working = selectPresetForCurrentPair()
        }
        .onChange(of: toLayout) { _, _ in
            working = selectPresetForCurrentPair()
        }
        .sheet(isPresented: $showNewSheet) {
            NewPresetSheet(
                fromLayout: fromLayout,
                toLayout: toLayout,
                onCreate: { preset in
                    store.save(preset)
                    working = preset
                    showNewSheet = false
                },
                onCancel: { showNewSheet = false }
            )
        }
        .confirmationDialog(
            String(localized: "Delete preset?"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible,
            presenting: working
        ) { preset in
            Button(String(localized: "Delete “\(preset.name)”"), role: .destructive) {
                let key = "\(fromLayout)|\(toLayout)"
                store.delete(id: preset.id)
                if settings.selectedPresetIds[key] == preset.id {
                    settings.selectedPresetIds.removeValue(forKey: key)
                }
                working = selectPresetForCurrentPair()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { preset in
            Text(String(localized: "“\(preset.name)” will be permanently removed. This cannot be undone."))
        }
    }

    /// Pick the preset the user previously chose for the current pair.
    /// Falls back to the first preset for the pair if nothing is saved.
    private func selectPresetForCurrentPair() -> LayoutMapperPreset? {
        let pair = LayoutPair(from: fromLayout, to: toLayout)
        let presets = store.presets(for: pair)
        guard !presets.isEmpty else { return nil }
        let key = "\(fromLayout)|\(toLayout)"
        if let savedId = settings.selectedPresetIds[key],
           let preset = presets.first(where: { $0.id == savedId }) {
            return preset
        }
        return presets.first
    }

    // MARK: - Header (pair + preset picker)

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // From layout
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "From"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Picker("", selection: $fromLayout) {
                        ForEach(layoutOptions, id: \.self) { l in
                            Text(l).tag(l)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                    .padding(.top, 14)

                // To layout
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "To"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Picker("", selection: $toLayout) {
                        ForEach(layoutOptions, id: \.self) { l in
                            Text(l).tag(l)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                // Preset picker (between two layouts and actions)
                if let working = working {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Preset"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Picker("", selection: Binding(
                            get: { working.id },
                            set: { newID in
                                if let p = store.preset(byID: newID) {
                                    self.working = p
                                    settings.selectedPresetIds["\(fromLayout)|\(toLayout)"] = p.id
                                }
                            }
                        )) {
                            ForEach(store.presets(for: LayoutPair(from: fromLayout, to: toLayout))) { p in
                                Text(p.name).tag(p.id as String?)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                Spacer()

                // Action buttons
                HStack(spacing: 6) {
                    Button {
                        showNewSheet = true
                    } label: {
                        Label(String(localized: "New"), systemImage: "plus")
                    }
                    .controlSize(.small)

                    Button {
                        // Auto-generate a fresh preset with UCKeyTranslate mapping
                        let mapping = KeyboardLayoutUtility.buildMapping(
                            fromLayout: fromLayout,
                            toLayout: toLayout
                        )
                        let auto = store.createPreset(
                            name: "\(fromLayout) → \(toLayout) (auto)",
                            from: fromLayout,
                            to: toLayout,
                            mapping: mapping
                        )
                        working = auto
                        // Make the new preset the active one for this pair
                        settings.selectedPresetIds["\(fromLayout)|\(toLayout)"] = auto.id
                    } label: {
                        Label(String(localized: "Auto"), systemImage: "wand.and.stars")
                    }
                    .controlSize(.small)
                    .disabled(fromLayout == toLayout || fromLayout == noneOption || toLayout == noneOption)

                    if working != nil {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .controlSize(.small)
                        .help(String(localized: "Delete"))
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.4))
            Text(String(localized: "No preset for this pair"))
                .font(.headline)
                .foregroundColor(.secondary)
            Text(String(localized: "Click “Auto” to generate a mapping, or “New” to start from scratch."))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var layoutOptions: [String] {
        var set = Set(availableLayouts)
        set.insert(noneOption)
        if !fromLayout.isEmpty { set.insert(fromLayout) }
        if !toLayout.isEmpty { set.insert(toLayout) }
        return Array(set).sorted { a, b in
            if a == noneOption { return true }
            if b == noneOption { return false }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }

    private func reloadLayouts() {
        availableLayouts = KeyboardLayoutUtility.enabledLayoutNames()
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

// MARK: - Working Editor Wrapper

struct WorkingEditor: View {
    @Binding var working: LayoutMapperPreset?
    let onSave: (LayoutMapperPreset) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        MapperEditorView(preset: Binding(
            get: { working ?? LayoutMapperPreset(name: "—", fromLayout: "?", toLayout: "?") },
            set: { newValue in
                working = newValue
                onSave(newValue)
            }
        ))
    }
}

// MARK: - New Preset Sheet

struct NewPresetSheet: View {
    let fromLayout: String
    let toLayout: String
    let onCreate: (LayoutMapperPreset) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var generateAuto: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "New preset"))
                .font(.headline)
            Text("\(fromLayout) → \(toLayout)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Name"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextField("", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle(String(localized: "Auto-generate mapping"), isOn: $generateAuto)

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.small)
                Button {
                    var p = LayoutMapperPreset(
                        name: name.isEmpty ? "\(fromLayout) → \(toLayout)" : name,
                        fromLayout: fromLayout,
                        toLayout: toLayout
                    )
                    if generateAuto {
                        p.mapping = KeyboardLayoutUtility.buildMapping(
                            fromLayout: fromLayout,
                            toLayout: toLayout
                        )
                    }
                    onCreate(p)
                } label: {
                    Label(String(localized: "Create"), systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
