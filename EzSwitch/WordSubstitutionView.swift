import SwiftUI

/// "Word Substitutions" tab inside the mapper window.
///
/// One-way word-level mappings for the active language pair. Each entry
/// says: when the user types `source` in the current layout direction,
/// auto-replace it with `target`. To get reverse behavior, add a second
/// entry for the opposite pair (the "Save both ways" checkbox does this).
struct WordSubstitutionView: View {

    private struct WordEntry: Identifiable {
        let source: String
        let target: String
        var id: String { source }
    }

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var wordStore = WordMapperStore.shared
    @State private var fromLayout: String = ""
    @State private var toLayout: String = ""
    @State private var showAddSheet: Bool = false
    @State private var showClearConfirmation: Bool = false
    @State private var deleteCandidate: String? = nil
    @State private var showHotkeySheet: Bool = false
    @State private var editingEntry: WordEntry? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()
            if currentPair == nil {
                pairMissingState
            } else {
                entriesList
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            fromLayout = settings.leftCommandLanguage
            toLayout = settings.rightCommandLanguage
        }
        .sheet(isPresented: $showAddSheet) {
            AddWordSheet(
                fromLayout: fromLayout,
                toLayout: toLayout,
                onAdd: { source, target, bothWays in
                    let pair = LayoutPair(from: fromLayout, to: toLayout)
                    wordStore.set(source: source, target: target, for: pair)
                    if bothWays {
                        let reverse = LayoutPair(from: toLayout, to: fromLayout)
                        wordStore.set(source: target, target: source, for: reverse)
                    }
                    showAddSheet = false
                },
                onCancel: { showAddSheet = false }
            )
        }
        .sheet(item: $editingEntry) { entry in
            EditWordSheet(
                fromLayout: fromLayout,
                toLayout: toLayout,
                originalSource: entry.source,
                originalTarget: entry.target,
                onSave: { newSource, newTarget in
                    if let pair = currentPair {
                        // If the source key changed, remove the old entry first
                        if newSource != entry.source {
                            wordStore.remove(source: entry.source, for: pair)
                        }
                        wordStore.set(source: newSource, target: newTarget, for: pair)
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
            Text(String(localized: "All word substitutions for \(fromLayout) → \(toLayout) will be removed."))
        }
    }

    private var currentPair: LayoutPair? {
        guard !fromLayout.isEmpty, !toLayout.isEmpty,
              fromLayout != "None", toLayout != "None",
              fromLayout != toLayout else { return nil }
        return LayoutPair(from: fromLayout, to: toLayout)
    }

    private var entries: [WordEntry] {
        guard let pair = currentPair else { return [] }
        let dict = wordStore.entries(for: pair)
        return dict.map { WordEntry(source: $0.key, target: $0.value) }
            .sorted { $0.source < $1.source }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "textformat.alt")
                .font(.system(size: 11))
                .frame(width: 16, height: 16)
                .foregroundColor(.secondary)
            Text(String(localized: "Word Substitutions"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
            Spacer()
            Button {
                showHotkeySheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "command")
                        .font(.system(size: 9))
                    Text(settings.wordRememberHotkey.displayLabel)
                        .font(.system(size: 11, design: .monospaced))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .help(String(localized: "Change hotkey for remembering words"))
            Toggle(String(localized: "Auto-replace"), isOn: $settings.enableWordSubstitution)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12))
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .controlSize(.small)
            .disabled(currentPair == nil)
            .help(String(localized: "Add substitution"))
            Button {
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
                Text(String(localized: "No word substitutions for \(fromLayout) → \(toLayout)"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(String(localized: "Type a word in any app, then press \(settings.wordRememberHotkey.displayLabel) to remember it"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(entries) {
                TableColumn(String(localized: "Source")) { row in
                    Text(row.source)
                        .font(.system(size: 13, design: .monospaced))
                }
                TableColumn(String(localized: "Target")) { row in
                    Text(row.target)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.accentColor)
                }
                TableColumn("") { row in
                    HStack(spacing: 10) {
                        Button(String(localized: "Edit")) {
                            editingEntry = row
                        }
                        .controlSize(.small)
                        Button {
                            deleteCandidate = row.source
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Delete"))
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(110)
            }
            .contextMenu(forSelectionType: WordEntry.ID.self) { ids in
                if let id = ids.first,
                   let entry = entries.first(where: { $0.id == id }) {
                    Button(String(localized: "Edit")) {
                        editingEntry = entry
                    }
                    Button(String(localized: "Delete"), role: .destructive) {
                        deleteCandidate = entry.source
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first,
                   let entry = entries.first(where: { $0.id == id }) {
                    editingEntry = entry
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

/// Sheet for adding a single (or both-ways) word substitution.
private struct AddWordSheet: View {
    let fromLayout: String
    let toLayout: String
    let onAdd: (_ source: String, _ target: String, _ bothWays: Bool) -> Void
    let onCancel: () -> Void

    @State private var source: String = ""
    @State private var target: String = ""
    @State private var bothWays: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Add Word Substitution"))
                .font(.system(size: 14, weight: .semibold))
            Text(String(localized: "Direction: \(fromLayout) → \(toLayout)"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            HStack {
                Text(String(localized: "Source"))
                    .frame(width: 80, alignment: .trailing)
                    .font(.system(size: 12))
                TextField(String(localized: "e.g. пше"), text: $source)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
            }
            HStack {
                Text(String(localized: "Target"))
                    .frame(width: 80, alignment: .trailing)
                    .font(.system(size: 12))
                TextField(String(localized: "e.g. git"), text: $target)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
            }
            Toggle(String(localized: "Save both ways (also adds the reverse)"), isOn: $bothWays)
                .font(.system(size: 12))
                .controlSize(.small)
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Add")) {
                    onAdd(source.trimmingCharacters(in: .whitespaces),
                          target.trimmingCharacters(in: .whitespaces),
                          bothWays)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(source.trimmingCharacters(in: .whitespaces).isEmpty ||
                          target.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// Sheet for editing an existing word substitution. Pre-fills the fields
/// with the current values; saves back to the same `source` key (or
/// removes the old one first if the user renames it).
private struct EditWordSheet: View {
    let fromLayout: String
    let toLayout: String
    let originalSource: String
    let originalTarget: String
    let onSave: (_ newSource: String, _ newTarget: String) -> Void
    let onCancel: () -> Void

    @State private var source: String = ""
    @State private var target: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Edit Word Substitution"))
                .font(.system(size: 14, weight: .semibold))
            Text(String(localized: "Direction: \(fromLayout) → \(toLayout)"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            HStack {
                Text(String(localized: "Source"))
                    .frame(width: 80, alignment: .trailing)
                    .font(.system(size: 12))
                TextField(String(localized: "e.g. пше"), text: $source)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
            }
            HStack {
                Text(String(localized: "Target"))
                    .frame(width: 80, alignment: .trailing)
                    .font(.system(size: 12))
                TextField(String(localized: "e.g. git"), text: $target)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save")) {
                    onSave(source.trimmingCharacters(in: .whitespaces),
                          target.trimmingCharacters(in: .whitespaces))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(source.trimmingCharacters(in: .whitespaces).isEmpty ||
                          target.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            source = originalSource
            target = originalTarget
        }
    }
}
