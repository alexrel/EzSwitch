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

    var initialMode: EditorMode = .character

    /// The preset being edited. `nil` means we are about to create a new one
    /// (after the user picks a pair and clicks "New" or "Auto").
    @State private var working: LayoutMapperPreset? = nil
    @State private var showNewSheet: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var mode: EditorMode = .character

    enum EditorMode: String, CaseIterable, Identifiable {
        case character = "Character Mappings"
        case word = "Word Substitutions"
        var id: String { rawValue }
    }

    private let noneOption = Constants.Default.noneLanguage

    var body: some View {
        VStack(spacing: 0) {
            // Top section: pair picker + segmented mode switcher.
            // Pinned to a fixed height so the From/To block and the
            // segmented control don't shift when switching between
            // tabs (each tab's content has a different intrinsic height).
            VStack(spacing: 0) {
                // 1) Pair + mode selector
                header
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Divider()
            }

            // 2) Editor (visual keyboard + test area + picker) or word list.
            Group {
                switch mode {
                case .character:
                    if let _ = working {
                        WorkingEditor(
                            working: $working,
                            presetsForPair: store.presets(for: LayoutPair(from: fromLayout, to: toLayout)),
                            onSelectPreset: { newID in
                                if let p = store.preset(byID: newID) {
                                    working = p
                                    settings.setSelectedPresetId(p.id, for: fromLayout, toLayout)
                                }
                            },
                            onNewPreset: { showNewSheet = true },
                            onDeletePreset: { showDeleteConfirmation = true },
                            onSave: { store.save($0) }
                        )
                    } else {
                        emptyState
                    }
                case .word:
                    WordSubstitutionView(selectedFromLayout: fromLayout, selectedToLayout: toLayout)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 560)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            reloadLayouts()
            if fromLayout.isEmpty {
                fromLayout = settings.leftCommandLanguage != Constants.Default.noneLanguage
                    ? settings.leftCommandLanguage
                    : Constants.Default.leftLanguage
            }
            if toLayout.isEmpty {
                toLayout = settings.rightCommandLanguage != Constants.Default.noneLanguage
                    ? settings.rightCommandLanguage
                    : Constants.Default.rightLanguage
            }
            mode = initialMode
            working = selectPresetForCurrentPair()
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchMapperMode)) { notif in
            if let newMode = notif.object as? EditorMode {
                mode = newMode
            }
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
                    settings.setSelectedPresetId(preset.id, for: fromLayout, toLayout)
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
                store.delete(id: preset.id)
                if settings.selectedPresetId(for: fromLayout, toLayout) == preset.id {
                    settings.setSelectedPresetId(nil, for: fromLayout, toLayout)
                }
                working = selectPresetForCurrentPair()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { preset in
            Text(String(localized: "“\(preset.name)” will be permanently removed. This cannot be undone."))
        }
    }

    /// Pick the preset the user previously chose for the current pair (in either order).
    /// Falls back to the first preset for the pair if nothing is saved.
    private func selectPresetForCurrentPair() -> LayoutMapperPreset? {
        let pair = LayoutPair(from: fromLayout, to: toLayout)
        let presets = store.presets(for: pair)
        guard !presets.isEmpty else { return nil }
        if let savedId = settings.selectedPresetId(for: fromLayout, toLayout),
           let preset = presets.first(where: { $0.id == savedId }) {
            return preset
        }
        return presets.first
    }

    // MARK: - Header (pair picker + mode switcher)

    private var header: some View {
        HStack(spacing: 12) {
            // Bidirectional language pair selector
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)

                Picker("", selection: $fromLayout) {
                    ForEach(layoutOptions, id: \.self) { l in
                        Text(l).tag(l)
                    }
                }
                .labelsHidden()
                .fixedSize()

                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.8))

                Picker("", selection: $toLayout) {
                    ForEach(layoutOptions, id: \.self) { l in
                        Text(l).tag(l)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            )

            Spacer()

            // Mode switcher (Character Mappings vs Word Substitutions)
            Picker("", selection: $mode) {
                ForEach(EditorMode.allCases) { m in
                    Text(LocalizedStringKey(m.rawValue)).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "keyboard")
                .font(.system(size: 52))
                .foregroundColor(.secondary.opacity(0.4))
            Text(String(localized: "No preset for this pair"))
                .font(.headline)
                .foregroundColor(.secondary)
            Text(String(localized: "Click “Auto” to generate a mapping, or “New” to start from scratch."))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            HStack(spacing: 10) {
                Button {
                    showNewSheet = true
                } label: {
                    Label(String(localized: "New"), systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button {
                    let mapping = KeyboardLayoutUtility.buildMapping(
                        fromLayout: fromLayout,
                        toLayout: toLayout
                    )
                    let auto = store.createPreset(
                        name: "\(fromLayout) ↔ \(toLayout) (auto)",
                        from: fromLayout,
                        to: toLayout,
                        mapping: mapping
                    )
                    working = auto
                    settings.setSelectedPresetId(auto.id, for: fromLayout, toLayout)
                } label: {
                    Label(String(localized: "Auto-generate"), systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(fromLayout == toLayout || fromLayout == noneOption || toLayout == noneOption)
            }
            .padding(.top, 4)
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
    let presetsForPair: [LayoutMapperPreset]
    let onSelectPreset: (String) -> Void
    let onNewPreset: () -> Void
    let onDeletePreset: () -> Void
    let onSave: (LayoutMapperPreset) -> Void

    var body: some View {
        MapperEditorView(
            preset: Binding(
                get: { working ?? LayoutMapperPreset(name: "—", fromLayout: "?", toLayout: "?") },
                set: { newValue in
                    working = newValue
                    onSave(newValue)
                }
            ),
            presetsForPair: presetsForPair,
            onSelectPreset: onSelectPreset,
            onNewPreset: onNewPreset,
            onDeletePreset: onDeletePreset
        )
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
