import Cocoa

/// Clipboard management with full save/restore of all data types
final class ClipboardManager {
    static let shared = ClipboardManager()

    private init() {}

    // MARK: - Types

    /// Saved clipboard state (all data types)
    struct ClipboardState {
        let items: [ItemData]
        let changeCount: Int

        var isEmpty: Bool { items.isEmpty }

        /// Data for a single clipboard item
        struct ItemData {
            let types: [NSPasteboard.PasteboardType]
            let dataByType: [NSPasteboard.PasteboardType: Data]
        }
    }

    // MARK: - Public API

    /// Save full clipboard state (all types: text, images, files, etc.)
    func saveState() -> ClipboardState {
        let pb = NSPasteboard.general
        var items: [ClipboardState.ItemData] = []

        if let pasteboardItems = pb.pasteboardItems {
            for item in pasteboardItems {
                var dataByType: [NSPasteboard.PasteboardType: Data] = [:]
                let types = item.types

                for type in types {
                    if let data = item.data(forType: type) {
                        dataByType[type] = data
                    }
                }

                if !dataByType.isEmpty {
                    items.append(ClipboardState.ItemData(types: types, dataByType: dataByType))
                }
            }
        }

        print("📋 [Clipboard] Saved \(items.count) items, \(items.flatMap { $0.types }.count) types")
        return ClipboardState(items: items, changeCount: pb.changeCount)
    }

    /// Restore full clipboard state
    func restoreState(_ state: ClipboardState) {
        let pb = NSPasteboard.general

        guard !state.isEmpty else {
            // Buffer was empty — clear it
            pb.clearContents()
            print("📋 [Clipboard] Restored empty state")
            return
        }

        pb.clearContents()

        var restoredItems: [NSPasteboardItem] = []

        for itemData in state.items {
            let newItem = NSPasteboardItem()

            for type in itemData.types {
                if let data = itemData.dataByType[type] {
                    newItem.setData(data, forType: type)
                }
            }

            restoredItems.append(newItem)
        }

        pb.writeObjects(restoredItems)
        print("📋 [Clipboard] Restored \(restoredItems.count) items")
    }

    // MARK: - Convenience Methods

    /// Set string to clipboard (for temporary use during transformation)
    func setString(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }

    /// Set marker in clipboard and return changeCount
    func setMarker() -> (marker: String, changeCount: Int) {
        let pb = NSPasteboard.general
        let marker = "__EZ_\(arc4random())__"
        pb.clearContents()
        pb.setString(marker, forType: .string)
        return (marker, pb.changeCount)
    }

    /// Get string from clipboard
    func getString() -> String? {
        return NSPasteboard.general.string(forType: .string)
    }

    /// Current changeCount
    var changeCount: Int {
        return NSPasteboard.general.changeCount
    }

    /// Wait for clipboard to change after copy
    func waitForChange(marker: String, markerCount: Int, timeoutMs: Int = 350, pollStepUs: useconds_t = 3_000) -> String? {
        let pb = NSPasteboard.general
        let steps = max(1, (timeoutMs * 1000) / Int(pollStepUs))

        for _ in 0..<steps {
            if pb.changeCount > markerCount {
                if let s = pb.string(forType: .string), !s.isEmpty, s != marker {
                    return s
                }
            }
            usleep(pollStepUs)
        }
        return nil
    }
}
