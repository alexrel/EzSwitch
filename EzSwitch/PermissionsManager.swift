import Cocoa
import Foundation

class PermissionsManager {
    static let shared = PermissionsManager()
    
    var isAccessibilityGranted: Bool {
        return AXIsProcessTrusted()
    }
    
    @discardableResult
    func checkAccessibilityPermissions() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        
        if !trusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.showPermissionAlert()
            }
        }
        
        return trusted
    }
    
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Permission Required")
        alert.informativeText = String(localized: "Add EzSwitch to:") + "\n" + String(localized: "System Settings → Privacy & Security → Accessibility")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Open Settings"))
        alert.addButton(withTitle: String(localized: "Later"))
        
        if alert.runModal() == .alertFirstButtonReturn {
            openSecurityPreferences()
        }
    }
    
    func openSecurityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
