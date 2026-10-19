import Cocoa
import OSLog
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
        // Height is the *minimum* preferred size; SwiftUI can grow it with fixedSize
        popover.contentSize = NSSize(width: 420, height: 200)
        popover.behavior = .transient
        
        // Create ViewController with settings
        let settingsVC = NSHostingController(rootView: SettingsView())
        popover.contentViewController = settingsVC
        
        super.init()
        
        // Configure status bar
        setupStatusBar()
    }
    
    private func setupStatusBar() {
        guard let button = statusItem.button else {
            Log.app.error("Status item has no button — the menu bar icon will not work")
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
    }
    
    private func updateTooltip() {
        guard let button = statusItem.button else { return }
        
        let settings = SettingsManager.shared
        let accessibility = AXIsProcessTrusted()
        
        var status = String(localized: "EzSwitch") + "\n"
        status += accessibility ? String(localized: "✅ Access granted") : String(localized: "❌ Permissions required")
        
        if settings.commandSwitchEnabled {
            status += "\n\n\(settings.switchModifier.displayName):"
            if settings.leftCommandLanguage != Constants.Default.noneLanguage {
                status += "\n  Left → \(settings.leftCommandLanguage)"
            }
            if settings.rightCommandLanguage != Constants.Default.noneLanguage {
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
            Log.app.error("Status item lost its button — cannot toggle the settings popover")
            return
        }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Update contentViewController when opening
            let settingsVC = NSHostingController(rootView: SettingsView())
            popover.contentViewController = settingsVC
            
            // Show popover
            popover.show(relativeTo: button.bounds,
                        of: button,
                        preferredEdge: .minY)
            
            // Activate application
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
