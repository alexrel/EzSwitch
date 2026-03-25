import Cocoa
import SwiftUI

class StatusBarController: NSObject {
    private var statusBar: NSStatusBar
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    
    override init() {
        statusBar = NSStatusBar.system
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        
        // Configure popover size and behavior
        popover.contentSize = NSSize(width: 420, height: 520)
        popover.behavior = .transient
        
        // Create ViewController with settings
        let settingsVC = NSHostingController(rootView: SettingsView())
        popover.contentViewController = settingsVC
        
        super.init()
        
        // Configure status bar
        setupStatusBar()
        
        print("✅ StatusBarController initialized")
    }
    
    private func setupStatusBar() {
        guard let button = statusItem.button else {
            print("❌ Failed to get button for status item")
            return
        }
        
        // Configure icon (TEMPLATE for automatic theme adaptation)
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            if let image = NSImage(systemSymbolName: "keyboard.fill", accessibilityDescription: "EzSwitch") {
                let templateImage = image.withSymbolConfiguration(config)
                button.image = templateImage
                button.image?.isTemplate = true // ← CRITICAL: adapts to theme
            }
        } else {
            button.title = "⌨️"
        }
        
        // Configure action
        button.action = #selector(togglePopover(_:))
        button.target = self
        
        // Update tooltip
        updateTooltip()
        
        print("✅ Status bar configured")
    }
    
    private func updateTooltip() {
        guard let button = statusItem.button else { return }
        
        let settings = SettingsManager.shared
        let accessibility = AXIsProcessTrusted()
        
        var status = String(localized: "EzSwitch") + "\n"
        status += accessibility ? String(localized: "✅ Access granted") : String(localized: "❌ Permissions required")
        
        if settings.commandSwitchEnabled {
            status += "\n\n⌘ Command:"
            if settings.leftCommandLanguage != "None" {
                status += "\n  Left → \(settings.leftCommandLanguage)"
            }
            if settings.rightCommandLanguage != "None" {
                status += "\n  Right → \(settings.rightCommandLanguage)"
            }
        }
        
        if settings.enableTransformKey {
            let icon = settings.transformKeyType.isShift ? "⇧" : "⌥"
            status += "\n\n\(icon) \(settings.transformKeyType.shortName) → Transformation"
        }
        
        status += "\n\n" + String(localized: "Click for settings")
        
        button.toolTip = status
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else {
            print("❌ Failed to get button for toggle")
            return
        }
        
        if popover.isShown {
            print("📪 Closing popover")
            popover.performClose(sender)
        } else {
            print("📬 Opening popover")
            
            // Update contentViewController when opening
            let settingsVC = NSHostingController(rootView: SettingsView())
            popover.contentViewController = settingsVC
            
            // Show popover
            popover.show(relativeTo: button.bounds,
                        of: button,
                        preferredEdge: .minY)
            
            // Activate application
            NSApp.activate(ignoringOtherApps: true)
            
            print("✅ Popover shown")
        }
    }
    
    func updateStatusIcon(enabled: Bool) {
        guard let button = statusItem.button else { return }
        
        if #available(macOS 11.0, *) {
            let imageName = enabled ? "keyboard.fill" : "keyboard"
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            
            if let image = NSImage(systemSymbolName: imageName, accessibilityDescription: "EzSwitch") {
                button.image = image.withSymbolConfiguration(config)
                button.image?.isTemplate = true // ← Template for adaptation
            }
        } else {
            button.title = enabled ? "⌨️" : "❌"
        }
        
        updateTooltip()
    }
}
