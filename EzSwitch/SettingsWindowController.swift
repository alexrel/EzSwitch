import SwiftUI
import AppKit
import Combine

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, switching, transformation, characters, words, permissions, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(appLocalized: "General")
        case .switching: return String(appLocalized: "Layout Switch")
        case .transformation: return String(appLocalized: "Text Transformation")
        case .characters: return String(appLocalized: "Character Mappings")
        case .words: return String(appLocalized: "Word Substitutions")
        case .permissions: return String(appLocalized: "Permissions")
        case .about: return String(appLocalized: "About EzSwitch")
        }
    }

    var subtitle: String {
        switch self {
        case .general: return String(appLocalized: "Startup and interface language")
        case .switching: return String(appLocalized: "Keys and keyboard layouts")
        case .transformation: return String(appLocalized: "Shortcut and correction behavior")
        case .characters: return String(appLocalized: "Layout pairs and mapping presets")
        case .words: return String(appLocalized: "Dictionary and remember shortcut")
        case .permissions: return String(appLocalized: "Keyboard access and system permissions")
        case .about: return String(appLocalized: "Version, author and project")
        }
    }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .switching: return "command"
        case .transformation: return "textformat.abc"
        case .characters: return "keyboard"
        case .words: return "text.book.closed"
        case .permissions: return "hand.raised"
        case .about: return "info.circle"
        }
    }
}

final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var section: SettingsSection = .general
    @Published var editorRequest = UUID()
    var requestedFromLayout: String?
    var requestedToLayout: String?

    func open(_ section: SettingsSection, usingSwitchPair: Bool) {
        if usingSwitchPair {
            let settings = SettingsManager.shared
            requestedFromLayout = settings.leftCommandLayout
            requestedToLayout = settings.rightCommandLayout
            editorRequest = UUID()
        }
        self.section = section
    }
}

/// Every entry point focuses the same window, including direct editor links.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var languageObservation: AnyCancellable?

    override init() {
        super.init()
        languageObservation = AppLocalization.shared.$languageCode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.window?.title = String(appLocalized: "EzSwitch Settings")
            }
    }

    func showWindow(section: SettingsSection? = nil, usingSwitchPair: Bool = false) {
        if let section {
            SettingsNavigation.shared.open(section, usingSwitchPair: usingSwitchPair)
        }
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 740),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        newWindow.title = String(appLocalized: "EzSwitch Settings")
        newWindow.contentViewController = NSHostingController(rootView: LocalizedContent { SettingsView() })
        newWindow.minSize = NSSize(width: 1020, height: 640)
        newWindow.isReleasedWhenClosed = false
        newWindow.collectionBehavior = [.fullScreenNone, .managed]
        newWindow.setFrameAutosaveName("EzSwitchSettings")
        if !newWindow.setFrameUsingName("EzSwitchSettings") { newWindow.center() }
        newWindow.delegate = self
        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        MapperStore.shared.flush()
        window = nil
    }
}

enum AppActions {
    static func restart() {
        MapperStore.shared.flush()
        UserDefaults.standard.synchronize()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    let alert = NSAlert(error: error)
                    alert.runModal()
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
