import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 1. Hide from Dock
        NSApp.setActivationPolicy(.accessory)
        print("✅ Application launched")

        // 2. Request required permissions (non-blocking)
        checkAndRequestPermissions()

        // 3. Initialize StatusBar
        statusBarController = StatusBarController()
        print("✅ StatusBar initialized")

        // 4. Start keyboard monitoring ALWAYS
        //    (HID listen-only tap requires Input Monitoring, not Accessibility)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            print("🔄 Starting KeyboardManager...")
            KeyboardManager.shared.startMonitoring()
        }

        // 5. If Accessibility not granted — warn user (for TextTransformer/selection)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if !AXIsProcessTrusted() {
                print("⚠️ No Accessibility — text transformation (AX) will not work until permission is granted.")
                self.showAccessibilityAlert()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        KeyboardManager.shared.stopMonitoring()
    }

    // MARK: - Permissions

    private func checkAndRequestPermissions() {
        print("\n🔍 PERMISSIONS CHECK")
        print(String(repeating: "=", count: 40))

        // Input Monitoring (Privacy & Security → Input Monitoring)
        let listenPreflight = CGPreflightListenEventAccess()
        print("• Input Monitoring (CGPreflightListenEventAccess): \(listenPreflight ? "✅ ACCESS GRANTED" : "❌ NO ACCESS")")
        if !listenPreflight {
            print("• Requesting Input Monitoring (CGRequestListenEventAccess)…")
            CGRequestListenEventAccess()
        }

        // Accessibility (Privacy & Security → Accessibility)
        let axSimple = AXIsProcessTrusted()
        print("• Accessibility (AXIsProcessTrusted): \(axSimple ? "✅ ACCESS GRANTED" : "❌ NO ACCESS")")

        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true
        ]
        let axPrompted = AXIsProcessTrustedWithOptions(options)
        print("• Accessibility prompt issued (AXIsProcessTrustedWithOptions): \(axPrompted ? "✅" : "❌")")

        print(String(repeating: "=", count: 40) + "\n")
    }

    // MARK: - Alerts / Settings

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Permission Required")
        
        let informativeText = NSTextField(wrappingLabelWithString: """
        \(String(localized: "EzSwitch requires the following permissions:"))
        
        \(String(localized: "1) Input Monitoring — to detect double Shift and single Cmd taps"))
        \(String(localized: "2) Accessibility — to transform selected text"))
        
        \(String(localized: "Add EzSwitch to:"))
        • \(String(localized: "System Settings → Privacy & Security → Input Monitoring"))
        • \(String(localized: "System Settings → Privacy & Security → Accessibility"))
        
        \(String(localized: "After granting permissions, restart the application."))
        """)
        informativeText.alignment = .left
        informativeText.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        informativeText.isEditable = false
        informativeText.isBordered = false
        informativeText.drawsBackground = false
        
        alert.accessoryView = informativeText
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Open Settings"))
        alert.addButton(withTitle: String(localized: "Later"))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openPrivacySettings()
        }
    }

    private func openPrivacySettings() {
        print("🛠️ Opening Privacy & Security…")

        // macOS 13+
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            if NSWorkspace.shared.open(url) {
                print("✅ Settings opened via URL")
                return
            }
        }

        // Fallback: just open System Settings
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
