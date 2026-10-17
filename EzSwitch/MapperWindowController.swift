import SwiftUI
import AppKit

extension Notification.Name {
    static let switchMapperMode = Notification.Name("EzSwitchSwitchMapperMode")
}

/// Manages a single instance of the Mapper Settings window.
/// Ensures only one window is open at a time, and brings it to front when re-opened.
final class MapperWindowController: NSObject, NSWindowDelegate {
    static let shared = MapperWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    /// Show the mapper settings window (or focus if already open)
    func showWindow(mode: MapperSettingsView.EditorMode = .character) {
        if let existing = window, existing.isVisible {
            NotificationCenter.default.post(name: .switchMapperMode, object: mode)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = MapperSettingsView(initialMode: mode)
        let hosting = NSHostingController(rootView: contentView)

        let windowSize = NSSize(width: 820, height: 640)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height),
            // NOTE: deliberately NOT using .fullSizeContentView here.
            // fullSizeContentView lets the window extend behind the menu bar,
            // which makes the content "jump up" when the auto-hiding menu
            // bar collapses. Keeping a normal title bar pins the window's
            // content rect to the visible screen area instead.
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = NSLocalizedString("EzSwitch — Custom Rules (Mappers & Words)", comment: "")
        newWindow.contentViewController = hosting
        newWindow.delegate = self
        newWindow.minSize = NSSize(width: 760, height: 540)
        newWindow.isReleasedWhenClosed = false
        newWindow.titlebarAppearsTransparent = false
        newWindow.toolbarStyle = .unified
        newWindow.isMovableByWindowBackground = true

        // Don't enter macOS "primary fullscreen" — that mode participates in
        // the menu bar auto-hide/show animation and causes the visible
        // content to shift. We're a normal window with our own title bar.
        newWindow.collectionBehavior = [.fullScreenNone, .managed]

        // Center window on the screen with the cursor (avoids spawning off-screen
        // on multi-monitor setups). We override any saved frame from previous runs.
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let x = visible.midX - windowSize.width / 2
            let y = visible.midY - windowSize.height / 2
            newWindow.setFrame(
                NSRect(x: x, y: y, width: windowSize.width, height: windowSize.height),
                display: true
            )
        } else {
            newWindow.center()
        }

        // Show window
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
        print("🪟 [MapperWindow] Window opened")
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if let closing = window, notification.object as? NSWindow === closing {
            window = nil
            print("🪟 [MapperWindow] Window closed")
        }
    }
}
