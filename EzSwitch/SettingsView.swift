import SwiftUI

struct SettingsView: View {
    /// `SettingsManager` is a singleton that owns its own lifetime, so this
    /// view observes it rather than owning it with `@StateObject`.
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var wordStore = WordMapperStore.shared
    @ObservedObject private var mapperStore = MapperStore.shared

    @State private var availableLanguages: [String] = []
    @State private var isLoaded = false
    @State private var hasAccessibility = false
    @State private var showAboutPopover = false
    @State private var showHotkeySheet = false

    private let noneOption = Constants.Default.noneLanguage

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var gitCommitHash: String? {
        Bundle.main.infoDictionary?["GitCommitHash"] as? String
    }

    private var languagesForPicker: [String] {
        KeyboardLayoutUtility.layoutOptions(
            availableLanguages,
            including: [settings.leftCommandLanguage, settings.rightCommandLanguage]
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.93, green: 0.95, blue: 1.0),
                    Color(red: 0.96, green: 0.97, blue: 0.99)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 8) {
                // Compact header
                HStack(spacing: 9) {
                    if let appIcon = NSImage(named: "AppIcon") {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)
                            .cornerRadius(6)
                            .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
                    } else {
                        Image(systemName: "keyboard")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 28, height: 28)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                    }

                    Text(String(localized: "EzSwitch Settings"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Spacer()

                    Button {
                        showAboutPopover.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help(String(localized: "About EzSwitch"))
                    .popover(isPresented: $showAboutPopover, arrowEdge: .bottom) {
                        aboutPopoverContent
                    }

                    Circle()
                        .fill(hasAccessibility ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                        .help(hasAccessibility ? String(localized: "Permissions granted") : String(localized: "Permissions required"))
                }
                .padding(.top, 4)

                // Cards laid out in a VStack so the popover sizes to natural content height
                VStack(spacing: 8) {
                    if !hasAccessibility {
                        permissionCard
                    }

                    // Layout Switch card
                    SettingsCard(icon: switchModifierIcon, title: String(localized: "Layout Switch"), color: .blue) {
                        VStack(spacing: 6) {
                            Toggle(String(localized: "Enable"), isOn: $settings.commandSwitchEnabled)
                                .toggleStyle(CompactToggleStyle(tint: .blue))

                            if settings.commandSwitchEnabled {
                                VStack(spacing: 6) {
                                    modifierRow
                                    HStack(spacing: 8) {
                                        compactLanguagePicker(
                                            icon: "arrow.left",
                                            title: String(localized: "Left"),
                                            selection: $settings.leftCommandLanguage
                                        )
                                        compactLanguagePicker(
                                            icon: "arrow.right",
                                            title: String(localized: "Right"),
                                            selection: $settings.rightCommandLanguage
                                        )
                                    }
                                }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                            }
                        }
                    }

                    // Text Transformation card
                    SettingsCard(icon: "textformat", title: String(localized: "Text Transformation"), color: .purple) {
                        VStack(spacing: 6) {
                            Toggle(String(localized: "Enable"), isOn: $settings.enableTransformKey)
                                .toggleStyle(CompactToggleStyle(tint: .purple))

                            if settings.enableTransformKey {
                                VStack(spacing: 6) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "key.fill")
                                            .foregroundColor(.purple)
                                            .font(.system(size: 11))
                                            .frame(width: 14)
                                        Text(String(localized: "Key"))
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Picker("", selection: $settings.transformKeyType) {
                                            ForEach(TransformKeyType.allCases, id: \.self) { keyType in
                                                Text(keyType.displayName).tag(keyType)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                        .controlSize(.small)
                                        .focusable(false)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(Color.primary.opacity(0.035))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                    .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
                                            )
                                    )

                                    HStack(spacing: 12) {
                                        Toggle(String(localized: "Suppress in apps"), isOn: $settings.suppressTransformKey)
                                            .toggleStyle(CompactToggleStyle(tint: .purple))
                                        Spacer()
                                        Toggle(String(localized: "Switch layout after"), isOn: $settings.switchLayoutAfterTransform)
                                            .toggleStyle(CompactToggleStyle(tint: .purple))
                                    }
                                    .font(.system(size: 11))

                                    if settings.suppressTransformKey {
                                        HStack(spacing: 4) {
                                            Image(systemName: "info.circle")
                                                .foregroundColor(.orange)
                                                .font(.system(size: 10))
                                            Text(String(localized: "Blocks double Shift/Option in PHPStorm etc."))
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                        }
                                    }
                                }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                            }

                            Divider().opacity(0.3)

                            HStack {
                                Image(systemName: "keyboard.badge.ellipsis")
                                    .foregroundColor(.purple)
                                    .font(.system(size: 12))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(String(localized: "Character Mappings"))
                                        .font(.system(size: 12, weight: .medium))
                                    Text(currentMapperInfo)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                Spacer()
                                Button(action: openMappersWindow) {
                                    HStack(spacing: 3) {
                                        Text(String(localized: "Open"))
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.purple)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.purple.opacity(0.12))
                                    )
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                            }

                            presetPickerView
                        }
                    }

                    // Word Substitutions card
                    SettingsCard(icon: "text.badge.checkmark", title: String(localized: "Word Substitutions"), color: .indigo) {
                        VStack(spacing: 6) {
                            Toggle(String(localized: "Auto-replace"), isOn: $settings.enableWordSubstitution)
                                .toggleStyle(CompactToggleStyle(tint: .indigo))

                            HStack {
                                Image(systemName: "character.book.closed")
                                    .foregroundColor(.indigo)
                                    .font(.system(size: 12))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(currentWordSubstitutionInfo)
                                        .font(.system(size: 11, weight: .medium))
                                    Button {
                                        showHotkeySheet = true
                                    } label: {
                                        HStack(spacing: 5) {
                                            Text(String(localized: "Quick remember:"))
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                            KeycapsView(tokens: settings.wordRememberHotkey.displayTokens, scale: .small)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .focusable(false)
                                    .help(String(localized: "Change hotkey for remembering words"))
                                }
                                Spacer()
                                Button(action: openWordsWindow) {
                                    HStack(spacing: 3) {
                                        Text(String(localized: "Open"))
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.indigo)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.indigo.opacity(0.12))
                                    )
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                            }
                        }
                    }

                    // System card
                    SettingsCard(icon: "gearshape.2", title: String(localized: "System"), color: .green) {
                        VStack(spacing: 6) {
                            HStack {
                                Image(systemName: "power")
                                    .foregroundColor(.green)
                                    .font(.system(size: 12))
                                Text(String(localized: "Launch at login"))
                                    .font(.system(size: 12))
                                Spacer()
                                Toggle("", isOn: $settings.launchAtLogin)
                                    .toggleStyle(CompactToggleStyle(tint: .green))
                                    .labelsHidden()
                            }
                        }
                    }

                    // Action buttons row
                    HStack(spacing: 8) {
                        Button(action: restartApplication) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(String(localized: "Restart"))
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.blue.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(Color.blue.opacity(0.18), lineWidth: 0.5)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)

                        Button(action: {
                            NSApplication.shared.terminate(nil)
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "power")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(String(localized: "Quit"))
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.red.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(Color.red.opacity(0.18), lineWidth: 0.5)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }

                    // Footer: version + author
                    HStack(spacing: 6) {
                        Button {
                            showAboutPopover.toggle()
                        } label: {
                            HStack(spacing: 5) {
                                Text("EzSwitch v\(appVersion)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("•")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text("by AlexReL")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .focusable(false)

                        Spacer()

                        Button {
                            NSWorkspace.shared.open(Constants.Link.repository)
                        } label: {
                            HStack(spacing: 3) {
                                Text("GitHub")
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            if !isLoaded {
                isLoaded = true
                reloadAvailableLanguages()
                checkPermissions()
            }
        }
        .sheet(isPresented: $showHotkeySheet) {
            HotkeyRecorderView(
                hotkey: $settings.wordRememberHotkey,
                actionName: String(localized: "Remember Word"),
                onClose: { showHotkeySheet = false }
            )
        }
    }

    // MARK: - About Popover

    private var aboutPopoverContent: some View {
        VStack(spacing: 10) {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .cornerRadius(11)
                    .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)
            } else {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.blue)
                    .frame(width: 48, height: 48)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(11)
            }

            VStack(spacing: 3) {
                Text("EzSwitch")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Version \(appVersion)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary.opacity(0.85))
                HStack(spacing: 4) {
                    Text("Build \(appBuild)")
                    if let hash = gitCommitHash, !hash.isEmpty {
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.4))
                        Text(hash)
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            }

            Divider()

            VStack(spacing: 5) {
                HStack(spacing: 4) {
                    Text(String(localized: "Author:"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("AlexReL")
                        .font(.system(size: 11, weight: .semibold))
                }

                Button {
                    NSWorkspace.shared.open(Constants.Link.repository)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 10, weight: .semibold))
                        Text(Constants.Link.repositoryDisplay)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }

            Text("© 2026 AlexReL · MIT License")
                .font(.system(size: 9.5))
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.top, 2)
        }
        .padding(16)
        .frame(width: 250)
    }

    // MARK: - Sub-views

    private var modifierRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.point.up.left.fill")
                .foregroundColor(.blue)
                .font(.system(size: 11))
                .frame(width: 14)
            Text(String(localized: "Key"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Picker("", selection: $settings.switchModifier) {
                ForEach(SwitchModifier.allCases, id: \.self) { mod in
                    Text(mod.displayName).tag(mod)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .focusable(false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private var presetPickerView: some View {
        let presets = availablePresetsForCurrentPair
        if !presets.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .foregroundColor(.purple)
                    .font(.system(size: 11))
                    .frame(width: 14)
                Text(String(localized: "Preset"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer(minLength: 2)
                Picker("", selection: presetSelectionBinding) {
                    ForEach(presets, id: \.id) { p in
                        Text(p.name).tag(p.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .focusable(false)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
                    )
            )
        }
    }

    /// Separate binding to avoid Swift compiler "unable to type-check" with inline closures.
    private var presetSelectionBinding: Binding<String> {
        let left = settings.leftCommandLanguage
        let right = settings.rightCommandLanguage
        let presets = availablePresetsForCurrentPair
        return Binding(
            get: {
                if let saved = settings.selectedPresetId(for: left, right),
                   presets.contains(where: { $0.id == saved }) {
                    return saved
                }
                return presets.first?.id ?? ""
            },
            set: { settings.setSelectedPresetId($0, for: left, right) }
        )
    }

    private var switchModifierIcon: String {
        switch settings.switchModifier {
        case .command: return "command"
        case .option:  return "option"
        }
    }

    // MARK: - Permission card

    private var permissionCard: some View {
        SettingsCard(icon: "exclamationmark.shield.fill", title: String(localized: "Permissions required"), color: .red) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Universal Access permission is required."))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Button(action: {
                    PermissionsManager.shared.openSecurityPreferences()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "gear")
                        Text(String(localized: "Open System Settings"))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(LinearGradient(
                        gradient: Gradient(colors: [.orange, .red]),
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
    }

    // MARK: - Compact language picker (in a 2-column layout)

    private func compactLanguagePicker(icon: String, title: String, selection: Binding<String>) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 14)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Spacer(minLength: 2)
            Picker("", selection: selection) {
                ForEach(languagesForPicker, id: \.self) { lang in
                    Text(lang == noneOption ? "—" : lang).tag(lang)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .focusable(false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Helpers

    private func checkPermissions() {
        hasAccessibility = PermissionsManager.shared.isAccessibilityGranted
    }

    private var availablePresetsForCurrentPair: [LayoutMapperPreset] {
        let left = settings.leftCommandLanguage
        let right = settings.rightCommandLanguage
        guard left != Constants.Default.noneLanguage, right != Constants.Default.noneLanguage else { return [] }
        let pair = LayoutPair(from: left, to: right)
        return MapperStore.shared.presets(for: pair)
    }

    private var currentMapperInfo: String {
        let left = settings.leftCommandLanguage
        let right = settings.rightCommandLanguage
        if left == Constants.Default.noneLanguage || right == Constants.Default.noneLanguage {
            return String(localized: "Pick a pair of languages")
        }
        let pair = LayoutPair(from: left, to: right)
        let presets = MapperStore.shared.presets(for: pair)
        if presets.isEmpty {
            return String(localized: "No mapping for this pair")
        }
        // Prefer the preset the user explicitly picked for this pair.
        let active = settings.selectedPresetId(for: left, right)
            .flatMap { id in presets.first(where: { $0.id == id }) }
            ?? presets.first
        if let preset = active {
            return String(localized: "\(preset.name) — \(preset.mappingCount) chars")
        }
        return String(localized: "No mapping for this pair")
    }

    private var currentWordSubstitutionInfo: String {
        let left = settings.leftCommandLanguage
        let right = settings.rightCommandLanguage
        if left == noneOption || right == noneOption {
            return String(localized: "Pick a pair of languages")
        }
        let pair = LayoutPair(from: left, to: right)
        let count = wordStore.entries(for: pair).count
        if count == 0 {
            return String(localized: "No words saved yet")
        }
        return String.localizedStringWithFormat(
            NSLocalizedString("%d words for current pair", comment: ""),
            count
        )
    }

    private func openMappersWindow() {
        MapperWindowController.shared.showWindow(mode: .character)
    }

    private func openWordsWindow() {
        MapperWindowController.shared.showWindow(mode: .word)
    }

    private func reloadAvailableLanguages() {
        availableLanguages = KeyboardLayoutUtility.enabledLayoutNames()
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func restartApplication() {
        let appURL = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [appURL.path]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - SettingsCard (compact version)

struct SettingsCard<Content: View>: View {
    let icon: String
    let title: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer()
            }

            content()
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.black.opacity(0.04), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 1.5)
        )
    }
}

// MARK: - Compact Toggle Style

struct CompactToggleStyle: ToggleStyle {
    var tint: Color = .green

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            configuration.label
            Spacer()
            ZStack {
                Capsule()
                    .fill(configuration.isOn ? tint : Color(NSColor.separatorColor).opacity(0.35))
                    .frame(width: 32, height: 18)
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: Color.black.opacity(0.18), radius: 1.5, x: 0, y: 1)
                    .offset(x: configuration.isOn ? 7 : -7)
                    .animation(.spring(response: 0.22, dampingFraction: 0.8), value: configuration.isOn)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                    configuration.isOn.toggle()
                }
            }
        }
        .focusable(false)
    }
}