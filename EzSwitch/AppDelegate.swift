import Cocoa
import ApplicationServices
import OSLog

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 1. Hide from Dock
        NSApp.setActivationPolicy(.accessory)

        // 2. Request required permissions (non-blocking)
        checkAndRequestPermissions()

        // 3. Initialize StatusBar
        statusBarController = StatusBarController()

        // 4. SettingsManager starts monitoring when the settings are initialized.
        //    Do not start it again here: that could override configured suppression.

        // 5. If Accessibility not granted — warn user (for TextTransformer/selection)
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Timing.accessibilityCheckDelaySec) {
            guard !AXIsProcessTrusted() else { return }
            Log.permissions.error("Accessibility not granted — text transformation will not work until permission is granted and the app is restarted")
            self.showAccessibilityAlert()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Flush debounced preset writes first — the termination below tears
        // down the keyboard pipeline, and a pending write must not be lost.
        MapperStore.shared.flush()
        KeyboardManager.shared.stopMonitoring()
    }

    // MARK: - Permissions

    private func checkAndRequestPermissions() {
        // Input Monitoring (Privacy & Security → Input Monitoring)
        let listenPreflight = CGPreflightListenEventAccess()
        if !listenPreflight {
            CGRequestListenEventAccess()
        }

        // Accessibility (Privacy & Security → Accessibility)
        // The prompt is issued here so the system dialog appears early.
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true
        ]
        let axPrompted = AXIsProcessTrustedWithOptions(options)

        // Informational only. Both requests above return false while the user
        // is still looking at the system dialog, so a "not granted" here is
        // not a failure — the actionable report happens once the user had
        // time to respond (see the deferred check in applicationDidFinishLaunching).
        Log.permissions.debug("Permissions at launch: Input Monitoring \(listenPreflight ? "granted" : "requested", privacy: .public), Accessibility \(axPrompted ? "granted" : "prompted", privacy: .public)")
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
        // macOS 13+
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy"),
           NSWorkspace.shared.open(url) {
            return
        }

        // Fallback: just open System Settings
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
