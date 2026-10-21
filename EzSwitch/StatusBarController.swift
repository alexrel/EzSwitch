import Cocoa
import OSLog
import SwiftUI
import Combine

class StatusBarController: NSObject {
    private var statusBar: NSStatusBar
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var observations = Set<AnyCancellable>()
    
    override init() {
        statusBar = NSStatusBar.system
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        
        // Configure popover size and behavior
        // Height is the *minimum* preferred size; SwiftUI can grow it with fixedSize
        popover.contentSize = NSSize(width: 360, height: 360)
        popover.behavior = .transient
        // Let the same SwiftUI background fill the native arrow region.
        // Foreground controls remain inside the popover's safe area.
        popover.hasFullSizeContent = true
        
        super.init()

        popover.contentViewController = NSHostingController(rootView: LocalizedContent {
            QuickControlsView { [weak self] section, usePair in
                self?.popover.performClose(nil)
                SettingsWindowController.shared.showWindow(section: section, usingSwitchPair: usePair)
            }
        })
        
        // Configure status bar
        setupStatusBar()

        SettingsManager.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateTooltip() }
            .store(in: &observations)
        PermissionsManager.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateTooltip() }
            .store(in: &observations)
        AppLocalization.shared.$languageCode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateTooltip() }
            .store(in: &observations)
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
        let permissions = PermissionsManager.shared
        
        var status = String(appLocalized: "EzSwitch") + "\n"
        if !permissions.allGranted {
            status += String(appLocalized: "Permissions required")
        } else if settings.isPaused {
            status += String(appLocalized: "Paused")
        } else if !settings.commandSwitchEnabled && !settings.enableTransformKey && !settings.enableWordSubstitution {
            status += String(appLocalized: "All features are off")
        } else {
            status += String(appLocalized: "Ready")
        }
        
        if settings.commandSwitchEnabled {
            status += "\n\n\(settings.switchModifier.displayName):"
            if settings.leftCommandLayout != Constants.Default.noneLanguage {
                status += "\n  \(String(appLocalized: "Left key")) → \(LayoutRegistry.displayName(forID: settings.leftCommandLayout))"
            }
            if settings.rightCommandLayout != Constants.Default.noneLanguage {
                status += "\n  \(String(appLocalized: "Right key")) → \(LayoutRegistry.displayName(forID: settings.rightCommandLayout))"
            }
        }
        
        if settings.enableTransformKey {
            status += "\n\n\(settings.transformKeyType.displayName) → \(String(appLocalized: "Text Transformation"))"
        }
        
        status += "\n\n" + String(appLocalized: "Click for quick controls")
        
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
            PermissionsManager.shared.refresh()
            updateTooltip()
            
            // Show popover
            popover.show(relativeTo: button.bounds,
                        of: button,
                        preferredEdge: .minY)
            
            // Activate application
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
