import SwiftUI

/// "Word Substitutions" tab inside the mapper window.
///
/// Unified word-level mappings for the active language pair. Each entry
/// says: when the user types `source`, auto-replace it with `target`.
/// Case (Shift/Caps) is automatically preserved by `WordMatcher`.
/// To get bidirectional behavior, check "Save both ways".
struct WordSubstitutionView: View {

    private struct WordEntry: Identifiable {
        let source: String
        let target: String
        let switchLayout: Bool
        var id: String { source }
    }

    var selectedFromLayout: String = ""
    var selectedToLayout: String = ""

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var wordStore = WordMapperStore.shared
    @State private var fromLayout: String = ""
    @State private var toLayout: String = ""
    @State private var showAddSheet: Bool = false
    @State private var showClearConfirmation: Bool = false
    @State private var deleteCandidate: String? = nil
    @State private var showHotkeySheet: Bool = false
    @State private var editingEntry: WordEntry? = nil

    /// Localized names of the selected pair. `fromLayout`/`toLayout` hold
    /// stable input source ids, which mean nothing to the user.
    private var displayFromLayout: String { LayoutRegistry.displayName(forID: fromLayout) }
    private var displayToLayout: String { LayoutRegistry.displayName(forID: toLayout) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .frame(height: 56)
            Divider()
            if currentPair == nil {
                pairMissingState
            } else {
                entriesList
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            fromLayout = !selectedFromLayout.isEmpty ? selectedFromLayout : settings.leftCommandLayout
            toLayout = !selectedToLayout.isEmpty ? selectedToLayout : settings.rightCommandLayout
        }
        .onChange(of: selectedFromLayout) { _, newVal in
            if !newVal.isEmpty { fromLayout = newVal }
        }
        .onChange(of: selectedToLayout) { _, newVal in
            if !newVal.isEmpty { toLayout = newVal }
        }
        .sheet(isPresented: $showAddSheet) {
            WordEntrySheet(
                title: String(localized: "Add Word Substitution"),
                fromLayout: fromLayout,
                toLayout: toLayout,
                initialSource: "",
                initialTarget: "",
                initialSwitchLayout: false,
                onSave: { source, target, switchLayout in
                    let pair = LayoutPair(from: fromLayout, to: toLayout)
                    wordStore.set(source: source, target: target, switchLayout: switchLayout, for: pair)
                    showAddSheet = false
                },
                onCancel: { showAddSheet = false }
            )
        }
        .sheet(item: $editingEntry) { entry in
            WordEntrySheet(
                title: String(localized: "Edit Word Substitution"),
                fromLayout: fromLayout,
                toLayout: toLayout,
                initialSource: entry.source,
                initialTarget: entry.target,
                initialSwitchLayout: entry.switchLayout,
                onSave: { newSource, newTarget, switchLayout in
                    if let pair = currentPair {
                        if newSource != entry.source {
                            wordStore.remove(source: entry.source, for: pair)
                        }
                        wordStore.set(source: newSource, target: newTarget, switchLayout: switchLayout, for: pair)
                    }
                    editingEntry = nil
                },
                onCancel: { editingEntry = nil }
            )
        }
        .sheet(isPresented: $showHotkeySheet) {
            HotkeyRecorderView(
                hotkey: $settings.wordRememberHotkey,
                actionName: String(localized: "Remember Word"),
                onClose: { showHotkeySheet = false }
            )
        }
        .confirmationDialog(
            String(localized: "Delete substitution?"),
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteCandidate
        ) { source in
            Button(String(localized: "Delete “\(source)”"), role: .destructive) {
                if let pair = currentPair {
                    wordStore.remove(source: source, for: pair)
                }
                deleteCandidate = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                deleteCandidate = nil
            }
        } message: { _ in
            Text(String(localized: "This will remove the substitution for this language pair."))
        }
        .confirmationDialog(
            String(localized: "Clear all substitutions for this pair?"),
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Clear all"), role: .destructive) {
                if let pair = currentPair {
                    wordStore.removeAll(for: pair)
                }
                showClearConfirmation = false
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                showClearConfirmation = false
            }
        } message: {
            Text(String(localized: "All word substitutions for \(displayFromLayout) ↔ \(displayToLayout) will be removed."))
        }
    }

    private var currentPair: LayoutPair? {
        guard !fromLayout.isEmpty, !toLayout.isEmpty,
              fromLayout != Constants.Default.noneLanguage,
              toLayout != Constants.Default.noneLanguage,
              fromLayout != toLayout else { return nil }
        return LayoutPair(from: fromLayout, to: toLayout)
    }

    private var entries: [WordEntry] {
        guard let pair = currentPair else { return [] }
        let dict = wordStore.entries(for: pair)
        return dict.map { key, value in
            let shouldSwitch = wordStore.shouldSwitchLayout(for: key, pair: pair)
            return WordEntry(source: key, target: value, switchLayout: shouldSwitch)
        }
        .sorted { $0.source < $1.source }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(String(localized: "Word Substitutions"))
                        .font(.title3.bold())
                    Text(verbatim: "\(entries.count) " + String(localized: "words"))
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.12))
                        )
                }
                Text("\(displayFromLayout) ↔ \(displayToLayout)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .fixedSize(horizontal: true, vertical: true)

            Spacer()

            Button {
                showHotkeySheet = true
            } label: {
                KeycapsView(tokens: settings.wordRememberHotkey.displayTokens, scale: .regular)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .help(String(localized: "Change hotkey for remembering words"))

            Toggle(String(localized: "Auto-replace"), isOn: $settings.enableWordSubstitution)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12))

            Button {
                showAddSheet = true
            } label: {
                Label(String(localized: "Add"), systemImage: "plus")
            }
            .controlSize(.small)
            .disabled(currentPair == nil)
            .help(String(localized: "Add substitution"))

            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .controlSize(.small)
            .disabled(entries.isEmpty)
            .help(String(localized: "Clear all"))
        }
    }

    @ViewBuilder
    private var pairMissingState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text(String(localized: "Configure a language pair in the popover first"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var entriesList: some View {
        if entries.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "textformat")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary.opacity(0.4))
                Text(String(localized: "No word substitutions for \(displayFromLayout) ↔ \(displayToLayout)"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Text(String(localized: "Type a word in any app, then press"))
                    KeycapsView(tokens: settings.wordRememberHotkey.displayTokens, scale: .small)
                    Text(String(localized: "to remember it"))
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // Column headers matching the card rows
                    HStack(spacing: 8) {
                        Text(String(localized: "Source"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(minWidth: 90, alignment: .leading)
                        Spacer()
                            .frame(width: 16)
                        Text(String(localized: "Target"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)

                    VStack(spacing: 5) {
                        ForEach(entries) { row in
                            MappingListRow(
                                source: row.source,
                                target: row.target,
                                modifier: nil,
                                isBidirectional: false,
                                switchLayout: row.switchLayout,
                                sourceWidth: 90,
                                onEdit: {
                                    editingEntry = row
                                },
                                onDelete: {
                                    deleteCandidate = row.source
                                }
                            )
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }
}

// MARK: - Unified Word Substitution Sheet (Add & Edit)

/// Sheet for adding or editing a word substitution.
/// Language-agnostic (`Source → Target`), with automatic translation button (`Auto`),
/// and bidirectional (`Save both ways`) toggle. Case is preserved automatically.
private struct WordEntrySheet: View {
    let title: String
    let fromLayout: String
    let toLayout: String
    let initialSource: String
    let initialTarget: String
    let initialSwitchLayout: Bool
    let onSave: (_ source: String, _ target: String, _ switchLayout: Bool) -> Void
    let onCancel: () -> Void

    @State private var source: String = ""
    @State private var target: String = ""
    @State private var switchLayout: Bool = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case source
        case target
    }

    /// Localized names of the pair. `fromLayout`/`toLayout` hold stable
    /// input source ids, which mean nothing to the user.
    private var displayFromLayout: String { LayoutRegistry.displayName(forID: fromLayout) }
    private var displayToLayout: String { LayoutRegistry.displayName(forID: toLayout) }

    var body: some View {
        VStack(spacing: 14) {
            // Top: Title on left, language pair badge on right
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(displayFromLayout) ↔ \(displayToLayout)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                    )
            }

            // Middle: Language-agnostic Source → Target boxes
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Source (what you type)"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField(String(localized: "e.g. ghbdtn or пше"), text: $source)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color(NSColor.textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(
                                    focusedField == .source
                                        ? Color.accentColor.opacity(0.75)
                                        : Color.primary.opacity(0.14),
                                    lineWidth: focusedField == .source ? 1.5 : 1
                                )
                        )
                        .focused($focusedField, equals: .source)
                }
                .frame(maxWidth: .infinity)

                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Target (replaced with)"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField(String(localized: "e.g. привет or git"), text: $target)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color(NSColor.textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(
                                    focusedField == .target
                                        ? Color.accentColor.opacity(0.75)
                                        : Color.primary.opacity(0.14),
                                    lineWidth: focusedField == .target ? 1.5 : 1
                                )
                        )
                        .focused($focusedField, equals: .target)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.16), lineWidth: 1)
            )

            // Options toggles
            VStack(alignment: .leading, spacing: 8) {
                Toggle(String(localized: "Switch keyboard layout to target language"), isOn: $switchLayout)
                    .font(.system(size: 12, weight: .medium))
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Bottom action buttons (matching Map key & Extra sheets)
            HStack {
                HStack(spacing: 6) {
                    Button {
                        source = ""
                        target = ""
                        focusedField = .source
                    } label: {
                        Label(String(localized: "Clear"), systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                    .focusable(false)

                    Button {
                        autoTranslateSourceToTarget()
                    } label: {
                        Label(String(localized: "Auto"), systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(source.trimmingCharacters(in: .whitespaces).isEmpty)
                    .focusable(false)
                    .help(String(localized: "Auto-translate Source into Target using active layout mapping"))
                }

                Spacer()

                HStack(spacing: 6) {
                    Button(action: onCancel) {
                        Label(String(localized: "Cancel"), systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                    .focusable(false)

                    Button {
                        onSave(
                            source.trimmingCharacters(in: .whitespaces),
                            target.trimmingCharacters(in: .whitespaces),
                            switchLayout
                        )
                    } label: {
                        Label(String(localized: "Save"), systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.return)
                    .disabled(source.trimmingCharacters(in: .whitespaces).isEmpty ||
                              target.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 460)
        .onAppear {
            source = initialSource
            target = initialTarget
            switchLayout = initialSwitchLayout
            // Give the sheet a beat to finish presenting before taking focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Timing.sheetFocusDelaySec) {
                focusedField = .source
            }
        }
    }

    /// Auto-translate `source` into `target` in whichever direction of `(fromLayout, toLayout)` matches `source`.
    private func autoTranslateSourceToTarget() {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        target = KeyboardLayoutUtility.autoTranslate(trimmed, from: fromLayout, to: toLayout)
    }
}
