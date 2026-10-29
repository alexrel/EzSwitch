import SwiftUI
import ServiceManagement

/// One home for preferences and the two existing rule editors.
struct SettingsView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @ObservedObject private var navigation = SettingsNavigation.shared
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var permissions = PermissionsManager.shared
    @State private var availableLayouts: [LayoutRegistry.Layout] = []
    @State private var loginStatus = SMAppService.mainApp.status
    private let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                if navigation.section == .characters || navigation.section == .words {
                    editor
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                            pageHeading
                            pageContent
                        }
                        .padding(SettingsLayout.pageInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 1020, minHeight: 600)
        .controlSize(.regular)
        .toggleStyle(LeadingSwitchToggleStyle())
        .onAppear(perform: refresh)
        .onChange(of: localization.languageCode) { _, _ in
            availableLayouts = LayoutRegistry.available()
        }
        .onReceive(permissionTimer) { _ in permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(SettingsSection.allCases) { section in
                        Button {
                            // Selecting a section keeps the editor's remembered pair.
                            navigation.requestedFromLayout = nil
                            navigation.requestedToLayout = nil
                            navigation.section = section
                        } label: {
                            HStack(alignment: .top, spacing: 11) {
                                Image(systemName: section.icon)
                                    .font(.system(size: 18, weight: .regular))
                                    .frame(width: 24, height: 24)
                                    .foregroundStyle(navigation.section == section ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(section.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(section.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(navigation.section == section ? Color.accentColor.opacity(0.13) : .clear,
                                        in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        .accessibilityAddTraits(navigation.section == section ? .isSelected : [])
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal, 10)
            }

            Divider().padding(.horizontal, 20)
            VStack(alignment: .leading, spacing: 8) {
                Label(statusTitle, systemImage: statusIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor)
            }
            .padding(16)
        }
        .frame(width: 230)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var statusTitle: String {
        if !permissions.allGranted { return String(appLocalized: "Permissions required") }
        if settings.isPaused { return String(appLocalized: "Paused") }
        if !settings.commandSwitchEnabled && !settings.enableTransformKey && !settings.enableWordSubstitution {
            return String(appLocalized: "All features are off")
        }
        return String(appLocalized: "Ready")
    }

    private var statusIcon: String {
        !permissions.allGranted ? "exclamationmark.circle" : (settings.isPaused ? "pause.circle" : "checkmark.circle")
    }

    private var statusColor: Color {
        !permissions.allGranted ? .orange : .primary
    }

    private var pageHeading: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(navigation.section.title).font(.system(size: 27, weight: .bold))
            Text(pageSubtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    private var pageSubtitle: String {
        if navigation.section == .characters || navigation.section == .words {
            return String(appLocalized: "Rules belong to the selected pair. Your switch-key assignments stay unchanged.")
        }
        return navigation.section.subtitle
    }

    @ViewBuilder private var pageContent: some View {
        switch navigation.section {
        case .general: generalPage
        case .switching: switchingPage
        case .transformation: transformationPage
        case .permissions: permissionsPage
        case .about: aboutPage
        case .characters, .words: EmptyView()
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
            pageHeading
            MapperSettingsView(
                initialMode: navigation.section == .characters ? .character : .word,
                initialFromLayout: navigation.requestedFromLayout,
                initialToLayout: navigation.requestedToLayout
            )
            .id("\(navigation.section.rawValue)-\(navigation.editorRequest)")
        }
        .padding(SettingsLayout.pageInset)
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
            SettingsGroup(title: String(appLocalized: "Startup")) {
                Toggle(String(appLocalized: "Launch at login"), isOn: $settings.launchAtLogin)
                    .toggleStyle(LeadingSwitchToggleStyle())
                    .onChange(of: settings.launchAtLogin) { _, _ in loginStatus = SMAppService.mainApp.status }
                Text(String(appLocalized: "EzSwitch runs in the menu bar without a Dock icon."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if loginStatus == .requiresApproval {
                    Text(String(appLocalized: "Allow EzSwitch in Login Items to finish enabling startup."))
                        .font(.system(size: 12)).foregroundStyle(.orange)
                    Button(String(appLocalized: "Open Login Items")) { SMAppService.openSystemSettingsLoginItems() }
                } else if settings.launchAtLogin && loginStatus != .enabled {
                    Text(String(appLocalized: "Startup is not enabled in macOS. Check Login Items."))
                        .font(.system(size: 12)).foregroundStyle(.orange)
                    Button(String(appLocalized: "Open Login Items")) { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            Divider()
            SettingsGroup(title: String(appLocalized: "Interface")) {
                PreferenceRow(title: String(appLocalized: "App language")) {
                    SettingsPicker(String(appLocalized: "App language"), selection: $settings.interfaceLanguage,
                                   options: AppLanguage.allCases.map { ($0, $0.title) })
                }
                Text(String(appLocalized: "Interface language does not change your keyboard layouts."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var switchingPage: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
            Toggle(String(appLocalized: "Enable layout switching"), isOn: $settings.commandSwitchEnabled)
                .toggleStyle(LeadingSwitchToggleStyle())
            SettingsGroup(title: String(appLocalized: "Switch keys")) {
                PreferenceRow(title: String(appLocalized: "Modifier key")) {
                    SettingsPicker(String(appLocalized: "Modifier key"), selection: $settings.switchModifier,
                                   options: SwitchModifier.allCases.map { ($0, $0.displayName) })
                }
                Text(String(appLocalized: "Tap a modifier on its own to switch layouts. Hold it with another key to use normal shortcuts."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().padding(.vertical, 6)
                layoutRow(title: String(appLocalized: "Left key"), selection: $settings.leftCommandLayout)
                layoutRow(title: String(appLocalized: "Right key"), selection: $settings.rightCommandLayout)
            }
            .disabled(!settings.commandSwitchEnabled)
            Divider()
            SettingsGroup(title: String(appLocalized: "Rules for this pair")) {
                Text(pairTitle).font(.system(size: 13, weight: .medium))
                HStack(spacing: 12) {
                    Button(String(appLocalized: "Character Mappings")) { openEditor(.characters) }
                    Button(String(appLocalized: "Word Substitutions")) { openEditor(.words) }
                }
            }
        }
    }

    private var transformationPage: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
            Toggle(String(appLocalized: "Enable text transformation"), isOn: $settings.enableTransformKey)
                .toggleStyle(LeadingSwitchToggleStyle())
            SettingsGroup(title: String(appLocalized: "Shortcut")) {
                PreferenceRow(title: String(appLocalized: "Double-tap key")) {
                    SettingsPicker(String(appLocalized: "Double-tap key"), selection: $settings.transformKeyType,
                                   options: TransformKeyType.allCases.map { ($0, "\($0.isShift ? "⇧" : "⌥")  \($0.displayName)") })
                }
                Text(String(appLocalized: "Correct selected text or the last typed word, for example ghbdtn → привет."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .disabled(!settings.enableTransformKey)
            Divider()
            SettingsGroup(title: String(appLocalized: "Behavior")) {
                Toggle(String(appLocalized: "Switch to the result layout after correction"), isOn: $settings.switchLayoutAfterTransform)
                Toggle(String(appLocalized: "Do not pass the double tap to other apps"), isOn: $settings.suppressTransformKey)
                Text(String(appLocalized: "Prevents the same double tap from opening actions such as Search Everywhere in JetBrains IDEs."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(LeadingSwitchToggleStyle())
            .disabled(!settings.enableTransformKey)
            Divider()
            Button(String(appLocalized: "Edit character mappings…")) { openEditor(.characters) }
        }
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
            permissionRow(
                title: String(appLocalized: "Accessibility"),
                description: String(appLocalized: "Allows EzSwitch to replace and correct text in other apps."),
                granted: permissions.isAccessibilityGranted,
                action: permissions.openSecurityPreferences
            )
            Divider()
            permissionRow(
                title: String(appLocalized: "Input Monitoring"),
                description: String(appLocalized: "Allows EzSwitch to detect your switch keys and shortcuts."),
                granted: permissions.isInputMonitoringGranted,
                action: permissions.openInputMonitoringPreferences
            )
            Divider()
            Text(String(appLocalized: "After granting permissions, restart the application."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(String(appLocalized: "Check again")) { permissions.refresh() }
                Button(String(appLocalized: "Restart"), action: AppActions.restart)
            }
        }
    }

    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
            HStack(spacing: 18) {
                if let icon = NSImage(named: "AppIcon") {
                    Image(nsImage: icon).resizable().frame(width: 96, height: 96)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "EzSwitch").font(.system(size: 22, weight: .semibold))
                    Text(String(appLocalized: "Version \(appVersion)"))
                    Text(String(appLocalized: "Build \(appBuild)"))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            Text(String(appLocalized: "Keyboard layout switching, text correction and a dictionary that learns your words."))
                .foregroundStyle(.secondary)
            Divider()
            LabeledContent(String(appLocalized: "Author:"), value: "AlexReL")
            Link(destination: Constants.Link.repository) {
                Label(String(appLocalized: "View on GitHub"), systemImage: "arrow.up.right.square")
            }
            Text(verbatim: "© 2026 AlexReL · MIT License").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"
    }
    private var appBuild: String {
        Bundle.main.infoDictionary?["GitCommitHash"] as? String ?? "dev"
    }
    private var pairTitle: String {
        "\(LayoutRegistry.displayName(forID: settings.leftCommandLayout)) ↔ \(LayoutRegistry.displayName(forID: settings.rightCommandLayout))"
    }
    private var layoutOptions: [LayoutRegistry.Layout] {
        LayoutRegistry.switcherOptions(availableLayouts, including: [settings.leftCommandLayout, settings.rightCommandLayout])
    }

    private func layoutRow(title: String, selection: Binding<String>) -> some View {
        PreferenceRow(title: title) {
            SettingsPicker(title, selection: selection, options: layoutOptions.map { ($0.id, $0.label) })
        }
    }

    private func permissionRow(title: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Label(granted ? String(appLocalized: "Granted") : String(appLocalized: "Not granted"),
                      systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(granted ? .green : .orange).font(.system(size: 12))
            }
            Text(description).font(.system(size: 12)).foregroundStyle(.secondary)
            Button(String(appLocalized: "Open System Settings"), action: action)
        }
    }

    private func openEditor(_ section: SettingsSection) {
        navigation.open(section, usingSwitchPair: true)
    }

    private func refresh() {
        permissions.refresh()
        availableLayouts = LayoutRegistry.available()
        loginStatus = SMAppService.mainApp.status
    }
}

private struct SettingsGroup<Content: View>: View {
    @ObservedObject private var localization = AppLocalization.shared
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 14, weight: .semibold)).padding(.bottom, 2)
            content()
        }
    }
}

private struct PreferenceRow<Control: View>: View {
    @ObservedObject private var localization = AppLocalization.shared
    let title: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 20) {
            Text(title).font(.system(size: 13))
            Spacer(minLength: 16)
            control()
                .frame(width: SettingsLayout.controlWidth)
        }
        .frame(minHeight: 26)
    }
}
