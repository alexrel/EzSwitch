import SwiftUI
import Carbon

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared

    @State private var availableLanguages: [String] = []
    @State private var isLoaded = false
    @State private var hasAccessibility = false

    private let noneOption = "None"

    private var languagesForPicker: [String] {
        var set = Set(availableLanguages)
        set.insert(noneOption)
        set.insert(settings.leftCommandLanguage)
        set.insert(settings.rightCommandLanguage)

        return Array(set).sorted { a, b in
            if a == noneOption { return true }
            if b == noneOption { return false }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }

    // Pre-computed current pair key for preset storage
    private var currentPairKey: String {
        "\(settings.leftCommandLanguage)|\(settings.rightCommandLanguage)"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.94, green: 0.96, blue: 1.0),
                    Color(red: 0.96, green: 0.97, blue: 0.99)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 8) {
                // Compact header
                HStack(spacing: 10) {
                    if let appIcon = NSImage(named: "AppIcon") {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                            .cornerRadius(7)
                            .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
                    } else {
                        Image(systemName: "keyboard")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 32, height: 32)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(7)
                    }

                    Text(String(localized: "EzSwitch Settings"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Spacer()

                    Circle()
                        .fill(hasAccessibility ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
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
                                            .frame(width: 16)
                                        Text(String(localized: "Key"))
                                            .font(.system(size: 12))
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

                            Divider().opacity(0.3)

                            HStack {
                                Image(systemName: "keyboard.badge.ellipsis")
                                    .foregroundColor(.indigo)
                                    .font(.system(size: 12))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(String(localized: "Keyboard Mappers"))
                                        .font(.system(size: 12, weight: .medium))
                                    Text(currentMapperInfo)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                Spacer()
                                Button(action: openMappersWindow) {
                                    Text(String(localized: "Open"))
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .tint(.indigo)
                            }

                            presetPickerView
                        }
                    }

                    // Action buttons row
                    HStack(spacing: 8) {
                        Button(action: restartApplication) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text(String(localized: "Restart"))
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.blue.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)

                        Button(action: {
                            NSApplication.shared.terminate(nil)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "power")
                                Text(String(localized: "Quit"))
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.red.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
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
    }

    // MARK: - Sub-views

    private var modifierRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.point.up.left.fill")
                .foregroundColor(.blue)
                .font(.system(size: 11))
                .frame(width: 16)
            Text(String(localized: "Key"))
                .font(.system(size: 11))
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
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.blue.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.blue.opacity(0.15), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private var presetPickerView: some View {
        let presets = availablePresetsForCurrentPair
        if !presets.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .foregroundColor(.indigo)
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(String(localized: "Preset"))
                    .font(.system(size: 12))
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
        }
    }

    /// Separate binding to avoid Swift compiler "unable to type-check" with inline closures.
    private var presetSelectionBinding: Binding<String> {
        let key = currentPairKey
        let presets = availablePresetsForCurrentPair
        return Binding(
            get: { settings.selectedPresetIds[key] ?? presets.first?.id ?? "" },
            set: { settings.selectedPresetIds[key] = $0 }
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
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.system(size: 11))
                .frame(width: 16)
            Text(title)
                .font(.system(size: 11))
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
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.blue.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.blue.opacity(0.15), lineWidth: 0.5)
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
        guard left != "None", right != "None" else { return [] }
        let pair = LayoutPair(from: left, to: right)
        return MapperStore.shared.presets(for: pair)
    }

    private var currentMapperInfo: String {
        let left = settings.leftCommandLanguage
        let right = settings.rightCommandLanguage
        if left == "None" || right == "None" {
            return String(localized: "Pick a pair of languages")
        }
        let pair = LayoutPair(from: left, to: right)
        let presets = MapperStore.shared.presets(for: pair)
        if presets.isEmpty {
            return String(localized: "No mapping for this pair")
        }
        // Prefer the preset the user explicitly picked for this pair.
        let key = "\(left)|\(right)"
        let active = settings.selectedPresetIds[key]
            .flatMap { id in MapperStore.shared.preset(byID: id) }
            ?? presets.first
        if let preset = active {
            return String(localized: "\(preset.name) — \(preset.mappingCount) chars")
        }
        return String(localized: "No mapping for this pair")
    }

    private func openMappersWindow() {
        MapperWindowController.shared.showWindow()
    }

    private func reloadAvailableLanguages() {
        availableLanguages = Self.fetchSelectableKeyboardLayouts()
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func fetchSelectableKeyboardLayouts() -> [String] {
        let filter: [String: Any] = [
            (kTISPropertyInputSourceCategory as String): (kTISCategoryKeyboardInputSource as String),
            (kTISPropertyInputSourceIsSelectCapable as String): true
        ]

        guard let rawList = TISCreateInputSourceList(filter as CFDictionary, false) else {
            return []
        }

        let list = rawList.takeRetainedValue() as NSArray
        var names = [String]()
        names.reserveCapacity(list.count)

        for item in list {
            let source = item as! TISInputSource

            if let enabledPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) {
                let enabledCF = Unmanaged<CFBoolean>.fromOpaque(enabledPtr).takeUnretainedValue()
                if !CFBooleanGetValue(enabledCF) { continue }
            }

            if let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
                let nameCF = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue()
                let name = nameCF as String
                if !name.isEmpty {
                    names.append(name)
                }
            }
        }

        return Array(Set(names))
    }

    private func restartApplication() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().path
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
            }
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
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
                    .fill(configuration.isOn ? tint : Color.gray.opacity(0.25))
                    .frame(width: 32, height: 17)
                Circle()
                    .fill(Color.white)
                    .frame(width: 13, height: 13)
                    .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 1)
                    .offset(x: configuration.isOn ? 7 : -7)
                    .animation(.easeInOut(duration: 0.18), value: configuration.isOn)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) {
                    configuration.isOn.toggle()
                }
            }
        }
        .focusable(false)
    }
}