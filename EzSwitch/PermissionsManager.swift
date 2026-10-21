import Cocoa
import Foundation
import Combine

final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published private(set) var isAccessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var isInputMonitoringGranted = CGPreflightListenEventAccess()

    var allGranted: Bool { isAccessibilityGranted && isInputMonitoringGranted }

    func refresh() {
        let accessibility = AXIsProcessTrusted()
        let inputMonitoring = CGPreflightListenEventAccess()
        if accessibility != isAccessibilityGranted { isAccessibilityGranted = accessibility }
        if inputMonitoring != isInputMonitoringGranted { isInputMonitoringGranted = inputMonitoring }
    }

    func openSecurityPreferences() {
        openPrivacyPane("Privacy_Accessibility")
    }

    func openInputMonitoringPreferences() {
        openPrivacyPane("Privacy_ListenEvent")
    }

    private func openPrivacyPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"),
           NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
