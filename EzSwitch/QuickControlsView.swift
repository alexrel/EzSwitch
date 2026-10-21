import SwiftUI

/// Session controls with the same icon and section treatment as the original panel.
struct QuickControlsView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var permissions = PermissionsManager.shared
    let openSettings: (SettingsSection?, Bool) -> Void
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon).resizable().frame(width: 28, height: 28)
                } else {
                    Image(systemName: "keyboard")
                        .font(.system(size: 20)).foregroundStyle(Color.accentColor)
                        .frame(width: 28, height: 28)
                }
                Text(verbatim: "EzSwitch")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Button { openSettings(.about, false) } label: {
                    Image(systemName: "info.circle").font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(String(appLocalized: "About EzSwitch"))
                .accessibilityLabel(String(appLocalized: "About EzSwitch"))
                .focusEffectDisabled()
                Button {
                    settings.isPaused.toggle()
                } label: {
                    Label(settings.isPaused ? String(appLocalized: "Resume") : String(appLocalized: "Pause"),
                          systemImage: settings.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(MenuActionButtonStyle())
                .focusEffectDisabled()
                Circle()
                    .fill(permissions.allGranted ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                    .help(permissions.allGranted ? String(appLocalized: "Permissions granted") : String(appLocalized: "Permissions required"))
                    .accessibilityLabel(permissions.allGranted ? String(appLocalized: "Permissions granted") : String(appLocalized: "Permissions required"))
            }

            if !permissions.allGranted {
                Button { openSettings(.permissions, false) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(String(appLocalized: "Permissions required")).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 8) {
                featureRow(
                    String(appLocalized: "Layout Switch"),
                    detail: "\(LayoutRegistry.displayName(forID: settings.leftCommandLayout)) ↔ \(LayoutRegistry.displayName(forID: settings.rightCommandLayout))",
                    icon: settings.switchModifier.isCommand ? "command" : "option", color: .blue, enabled: $settings.commandSwitchEnabled
                )
                featureRow(
                    String(appLocalized: "Text Transformation"),
                    detail: settings.transformKeyType.displayName,
                    icon: "textformat", color: .purple, enabled: $settings.enableTransformKey
                )
                featureRow(
                    String(appLocalized: "Word Substitutions"),
                    detail: String(appLocalized: "For all configured pairs"),
                    icon: "text.badge.checkmark", color: .indigo, enabled: $settings.enableWordSubstitution
                )
            }
            .disabled(settings.isPaused)

            HStack(spacing: 8) {
                Button { openSettings(nil, false) } label: {
                    Label(String(appLocalized: "Settings"), systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
                Button { openSettings(.words, true) } label: {
                    Label(String(appLocalized: "Dictionary"), systemImage: "character.book.closed")
                }
                Spacer(minLength: 0)
                Button { NSApp.terminate(nil) } label: {
                    Label(String(appLocalized: "Quit"), systemImage: "power")
                }
            }
            .buttonStyle(MenuActionButtonStyle())
            .focusEffectDisabled()
        }
        .controlSize(.regular)
        .padding(16)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { permissions.refresh() }
        .onReceive(timer) { _ in permissions.refresh() }
    }

    private func featureRow(_ title: String, detail: String, icon: String, color: Color, enabled: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: enabled).labelsHidden().toggleStyle(.switch)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor).opacity(0.35), lineWidth: 0.5)
        }
    }
}

/// An opaque fill keeps menu actions as light as the feature cards, including
/// when macOS would dim a native bordered button in an inactive popover.
private struct MenuActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 5))
            .opacity(isEnabled ? 1 : 0.5)
    }
}
