import SwiftUI

@main
struct EzSwitchApp: App {
    @ObservedObject private var localization = AppLocalization.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView() // Empty scene since we only use menu bar
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(String(appLocalized: "About EzSwitch")) {
                    SettingsWindowController.shared.showWindow(section: .about)
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button(String(appLocalized: "Settings…")) {
                    SettingsWindowController.shared.showWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appTermination) {
                Button(String(appLocalized: "Quit")) { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}
