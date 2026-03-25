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

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 0.90, green: 0.94, blue: 0.98)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    // Header with app icon and title in one line
                    HStack(spacing: 12) {
                        // App icon
                        if let appIcon = NSImage(named: "AppIcon") {
                            Image(nsImage: appIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 40, height: 40)
                                .cornerRadius(8)
                                .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                        } else {
                            // Fallback if AppIcon not available
                            Image(systemName: "keyboard")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundColor(.blue)
                                .frame(width: 40, height: 40)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }

                        // Title
                        Text(String(localized: "EzSwitch Settings"))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Spacer()
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 4)

                    // Permissions Card (FIRST - only if no access)
                    if !hasAccessibility {
                        SettingsCard(icon: "exclamationmark.shield", title: String(localized: "Permissions required"), color: .red) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(String(localized: "Universal Access permission is required"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Button(action: {
                                    PermissionsManager.shared.openSecurityPreferences()
                                }) {
                                    HStack {
                                        Image(systemName: "gear")
                                        Text(String(localized: "Open System Settings"))
                                    }
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                                    .background(LinearGradient(
                                        gradient: Gradient(colors: [.orange, .red]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                            }
                        }
                    }

                    // Command Switch Card
                    SettingsCard(icon: "command", title: String(localized: "Command Switch"), color: .blue) {
                        Toggle(String(localized: "Enable"), isOn: $settings.commandSwitchEnabled)
                            .toggleStyle(CustomToggleStyle())

                        if settings.commandSwitchEnabled {
                            VStack(spacing: 12) {
                                LanguagePickerRow(
                                    icon: "arrow.left",
                                    title: String(localized: "Left Command"),
                                    selection: $settings.leftCommandLanguage,
                                    options: languagesForPicker,
                                    noneOption: noneOption
                                )

                                LanguagePickerRow(
                                    icon: "arrow.right",
                                    title: String(localized: "Right Command"),
                                    selection: $settings.rightCommandLanguage,
                                    options: languagesForPicker,
                                    noneOption: noneOption
                                )
                            }
                            .padding(.top, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    // Text Transformation Card
                    SettingsCard(icon: "textformat", title: String(localized: "Text Transformation"), color: .purple) {
                        Toggle(String(localized: "Enable"), isOn: $settings.enableTransformKey)
                            .toggleStyle(CustomToggleStyle())

                        if settings.enableTransformKey {
                            VStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "key")
                                        .foregroundColor(.purple)
                                        .frame(width: 24)

                                    Text(String(localized: "Key"))
                                        .font(.subheadline)

                                    Spacer()

                                    Picker("", selection: $settings.transformKeyType) {
                                        ForEach(TransformKeyType.allCases, id: \.self) { keyType in
                                            Text(keyType.displayName).tag(keyType)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                    .focusable(false)
                                }

                                Toggle(String(localized: "Suppress in applications"), isOn: $settings.suppressTransformKey)
                                    .toggleStyle(CustomToggleStyle())

                                if settings.suppressTransformKey {
                                    HStack {
                                        Image(systemName: "info.circle")
                                            .foregroundColor(.orange)
                                        Text(String(localized: "Blocks double Shift/Option in PHPStorm etc."))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.leading, 8)
                                }

                                Toggle(String(localized: "Switch layout after"), isOn: $settings.switchLayoutAfterTransform)
                                    .toggleStyle(CustomToggleStyle())
                            }
                            .padding(.top, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    // Launch at Login Card
                    SettingsCard(icon: "power", title: String(localized: "Launch at login"), color: .green) {
                        Toggle(String(localized: "Enable"), isOn: $settings.launchAtLogin)
                            .toggleStyle(CustomToggleStyle())
                    }

                    // Current Assignments Card
                    if settings.commandSwitchEnabled || settings.enableTransformKey {
                        SettingsCard(icon: "list.bullet.rectangle", title: String(localized: "Current assignments:"), color: .orange) {
                            VStack(spacing: 8) {
                                if settings.commandSwitchEnabled {
                                    if settings.leftCommandLanguage != noneOption {
                                        AssignmentRow(
                                            icon: "⌘",
                                            iconColor: .blue,
                                            left: String(localized: "Left Command"),
                                            right: settings.leftCommandLanguage
                                        )
                                    }
                                    if settings.rightCommandLanguage != noneOption {
                                        AssignmentRow(
                                            icon: "⌘",
                                            iconColor: .blue,
                                            left: String(localized: "Right Command"),
                                            right: settings.rightCommandLanguage
                                        )
                                    }
                                }

                                if settings.enableTransformKey {
                                    AssignmentRow(
                                        icon: settings.transformKeyType.isShift ? "⇧" : "⌥",
                                        iconColor: .purple,
                                        left: settings.transformKeyType.displayName,
                                        right: String(localized: "Transformation")
                                    )
                                }
                            }
                        }
                    }

                    // Action Buttons
                    HStack(spacing: 12) {
                        Button(action: restartApplication) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text(String(localized: "Restart"))
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)

                        Spacer()

                        Button(action: {
                            NSApplication.shared.terminate(nil)
                        }) {
                            HStack {
                                Image(systemName: "power")
                                Text(String(localized: "Quit"))
                            }
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(LinearGradient(
                                gradient: Gradient(colors: [.red, .pink]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, 20)
            }
        }
        .frame(width: 400, height: 580)
        .onAppear {
            if !isLoaded {
                isLoaded = true
                reloadAvailableLanguages()
                checkPermissions()
            }
        }
    }

    private func checkPermissions() {
        hasAccessibility = PermissionsManager.shared.isAccessibilityGranted
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

// MARK: - Custom Components

struct SettingsCard<Content: View>: View {
    let icon: String
    let title: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 18, weight: .semibold))

                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(color == .red ? Color.red.opacity(0.1) : Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        )
    }
}

struct LanguagePickerRow: View {
    let icon: String
    let title: String
    @Binding var selection: String
    let options: [String]
    let noneOption: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)

            Text(title)
                .font(.subheadline)

            Spacer()

            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { language in
                    Text(language == noneOption ? "—" : language)
                        .tag(language)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .focusable(false)
        }
    }
}

struct AssignmentRow: View {
    let icon: String
    let iconColor: Color
    let left: String
    let right: String

    var body: some View {
        HStack {
            Text(icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
                .background(iconColor.opacity(0.1))
                .cornerRadius(6)

            Text(left)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()

            Text(right)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

struct CustomToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            Spacer()

            ZStack {
                Capsule()
                    .fill(configuration.isOn ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 40, height: 22)

                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(radius: 1)
                    .offset(x: configuration.isOn ? 9 : -9)
                    .animation(.easeInOut(duration: 0.2), value: configuration.isOn)
            }
            .onTapGesture {
                withAnimation {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}
