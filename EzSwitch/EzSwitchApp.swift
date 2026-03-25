import SwiftUI

@main
struct EzSwitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView() // Empty scene since we only use menu bar
        }
    }
}
