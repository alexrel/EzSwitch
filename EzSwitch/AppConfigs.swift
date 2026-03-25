import Foundation
import Cocoa

/// Word selection configuration for a specific application
struct AppWordSelectionConfig {
    /// Application bundle ID (e.g., "com.jetbrains.PhpStorm")
    let bundleId: String

    /// Human-readable name (for logs)
    let displayName: String

    /// Backward word selection method
    let wordSelectionMethod: WordSelectionMethod

    /// Additional notes
    let notes: String?

    init(bundleId: String, displayName: String, method: WordSelectionMethod, notes: String? = nil) {
        self.bundleId = bundleId
        self.displayName = displayName
        self.wordSelectionMethod = method
        self.notes = notes
    }
}

/// Word selection method
enum WordSelectionMethod: CustomStringConvertible {
    /// Option+Shift+Left - macOS standard (TextEdit, Safari, Notes)
    case optionShiftLeft

    /// Ctrl+Shift+Left - IDE standard (JetBrains, VSCode, Sublime)
    case ctrlShiftLeft

    /// Try both methods (Option first, then Ctrl)
    case auto

    var description: String {
        switch self {
        case .optionShiftLeft: return "Option+Shift+Left"
        case .ctrlShiftLeft: return "Ctrl+Shift+Left"
        case .auto: return "Auto"
        }
    }
}

/// Application configuration registry
final class AppConfigRegistry {
    static let shared = AppConfigRegistry()

    /// Default method for unknown applications
    let defaultMethod: WordSelectionMethod = .optionShiftLeft

    /// Application configurations
    /// Add new applications here as they are tested
    private let configs: [AppWordSelectionConfig] = [

        // MARK: - JetBrains IDEs
        AppWordSelectionConfig(
            bundleId: "com.jetbrains.PhpStorm",
            displayName: "PHPStorm",
            method: .ctrlShiftLeft,
            notes: "Option+Shift+Left selects entire line"
        ),
        AppWordSelectionConfig(
            bundleId: "com.jetbrains.intellij",
            displayName: "IntelliJ IDEA",
            method: .ctrlShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.jetbrains.WebStorm",
            displayName: "WebStorm",
            method: .ctrlShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.jetbrains.pycharm",
            displayName: "PyCharm",
            method: .ctrlShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.jetbrains.CLion",
            displayName: "CLion",
            method: .ctrlShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.jetbrains.goland",
            displayName: "GoLand",
            method: .ctrlShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.jetbrains.rubymine",
            displayName: "RubyMine",
            method: .ctrlShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.jetbrains.rider",
            displayName: "Rider",
            method: .ctrlShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.jetbrains.datagrip",
            displayName: "DataGrip",
            method: .ctrlShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.jetbrains.AppCode",
            displayName: "AppCode",
            method: .ctrlShiftLeft
        ),

        // MARK: - Other IDEs and editors
        AppWordSelectionConfig(
            bundleId: "com.sublimetext.4",
            displayName: "Sublime Text 4",
            method: .ctrlShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.sublimetext.3",
            displayName: "Sublime Text 3",
            method: .ctrlShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.microsoft.VSCode",
            displayName: "VS Code",
            method: .ctrlShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.microsoft.VSCodeInsiders",
            displayName: "VS Code Insiders",
            method: .ctrlShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.github.atom",
            displayName: "Atom",
            method: .ctrlShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.googlecode.iterm2",
            displayName: "iTerm2",
            method: .optionShiftLeft,
            notes: "Terminal, Option works"
        ),

        // MARK: - macOS standard applications (Option+Shift+Left)
        AppWordSelectionConfig(
            bundleId: "com.apple.TextEdit",
            displayName: "TextEdit",
            method: .optionShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.apple.Safari",
            displayName: "Safari",
            method: .optionShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.apple.Notes",
            displayName: "Notes",
            method: .optionShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.apple.mail",
            displayName: "Mail",
            method: .optionShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.apple.Pages",
            displayName: "Pages",
            method: .optionShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.apple.iWork.Numbers",
            displayName: "Numbers",
            method: .optionShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.apple.iWork.Keynote",
            displayName: "Keynote",
            method: .optionShiftLeft
        ),

        // MARK: - Browsers
        AppWordSelectionConfig(
            bundleId: "com.google.Chrome",
            displayName: "Google Chrome",
            method: .optionShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "org.mozilla.firefox",
            displayName: "Firefox",
            method: .optionShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.brave.Browser",
            displayName: "Brave",
            method: .optionShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.operasoftware.Opera",
            displayName: "Opera",
            method: .optionShiftLeft
        ),

        // MARK: - Messengers
        AppWordSelectionConfig(
            bundleId: "ru.keepcoder.Telegram",
            displayName: "Telegram",
            method: .optionShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.tinyspeck.slackmacgap",
            displayName: "Slack",
            method: .optionShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.hnc.Discord",
            displayName: "Discord",
            method: .optionShiftLeft
        ),

        // MARK: - Other applications
        AppWordSelectionConfig(
            bundleId: "com.apple.dt.Xcode",
            displayName: "Xcode",
            method: .optionShiftLeft,
            notes: "Xcode uses macOS standard"
        ),
        AppWordSelectionConfig(
            bundleId: "com.figma.Desktop",
            displayName: "Figma",
            method: .optionShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "notion.id",
            displayName: "Notion",
            method: .optionShiftLeft
        ),
        AppWordSelectionConfig(
            bundleId: "com.electron.obsidian",
            displayName: "Obsidian",
            method: .ctrlShiftLeft
        ),
    ]

    /// Index for fast lookup by bundleId
    private lazy var configIndex: [String: AppWordSelectionConfig] = {
        var index: [String: AppWordSelectionConfig] = [:]
        for config in configs {
            index[config.bundleId.lowercased()] = config
        }
        return index
    }()

    private init() {}

    /// Get configuration for an application
    func config(for bundleId: String?) -> AppWordSelectionConfig? {
        guard let bundleId = bundleId else { return nil }
        return configIndex[bundleId.lowercased()]
    }

    /// Get selection method for an application
    func wordSelectionMethod(for bundleId: String?) -> WordSelectionMethod {
        if let config = config(for: bundleId) {
            return config.wordSelectionMethod
        }
        return defaultMethod
    }

    /// Get Bundle ID of the currently active application
    static func frontmostAppBundleId() -> String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Get name of the currently active application
    static func frontmostAppName() -> String? {
        return NSWorkspace.shared.frontmostApplication?.localizedName
    }
}
