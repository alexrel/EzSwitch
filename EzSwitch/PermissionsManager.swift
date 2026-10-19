import Cocoa
import Foundation

class PermissionsManager {
    static let shared = PermissionsManager()
    
    var isAccessibilityGranted: Bool {
        return AXIsProcessTrusted()
    }

    func openSecurityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
