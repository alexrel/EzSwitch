import Foundation
import Carbon

/// Stable identity for a keyboard layout.
///
/// A layout's localized name is whatever the system reports for the current
/// language: `Russian – PC` under English, `Русская — ПК` under Russian. It
/// changes the moment the language changes, so it can never be persisted —
/// every stored name silently stops matching afterwards, and switching or
/// preset lookup quietly does nothing.
///
/// `kTISPropertyInputSourceID` (`com.apple.keylayout.RussianWin`) does not
/// change. That id is what EzSwitch stores everywhere; the localized name is
/// only ever derived from it, for display.
enum LayoutRegistry {

    /// A layout as offered to the user: stable `id` plus localized `name`.
    struct Layout: Identifiable, Hashable {
        /// Stable input source id — the persisted value.
        let id: String
        /// Localized name for the current language — the displayed value.
        let name: String

        /// What a picker shows for this row. The "no layout" row is drawn as
        /// an em dash rather than spelling out `None`, in every picker.
        var label: String { id == Constants.Default.noneLanguage ? "—" : name }
    }

    // MARK: - Enumeration

    /// Enabled, user-selectable keyboard layouts, sorted by localized name.
    static func available() -> [Layout] {
        var seen = Set<String>()
        var layouts: [Layout] = []

        for source in KeyboardLayoutUtility.availableInputSources() {
            guard KeyboardLayoutUtility.isEnabled(source),
                  let id = KeyboardLayoutUtility.inputSourceID(of: source),
                  let name = KeyboardLayoutUtility.localizedName(of: source),
                  !name.isEmpty,
                  seen.insert(id).inserted else { continue }
            layouts.append(Layout(id: id, name: name))
        }

        return layouts.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Picker options

    /// Rows for a switcher picker (the settings card).
    ///
    /// Every layout in `layouts`, plus `extras` that are configured but
    /// switched off in System Settings — a configured layout must not silently
    /// vanish from the selection. "None" comes first: either command key may
    /// legitimately be bound to nothing, and both keys may point at the same
    /// layout.
    static func switcherOptions(_ layouts: [Layout], including extras: [String] = []) -> [Layout] {
        let none = Constants.Default.noneLanguage
        var rows = mergeExtras(layouts, including: extras)
        if !rows.contains(where: { $0.id == none }) {
            rows.append(Layout(id: none, name: none))
        }
        return sortedForPicker(rows)
    }

    /// Rows for one side of a mapping pair (the mapper window).
    ///
    /// No "None" on the source side: there is always a layout to map from. The
    /// target side passes the chosen source as `excluded`, since a mapping
    /// from a layout to itself carries no information. If excluding it leaves
    /// nothing — the system has a single layout — "—" comes back so the picker
    /// still has a row to show.
    static func mapperOptions(
        _ layouts: [Layout],
        including extras: [String] = [],
        excluding excluded: String
    ) -> [Layout] {
        let rows = mergeExtras(layouts.filter { $0.id != excluded },
                               including: extras.filter { $0 != excluded })
        if rows.isEmpty {
            return [Layout(id: Constants.Default.noneLanguage, name: Constants.Default.noneLanguage)]
        }
        return sortedForPicker(rows)
    }

    /// `layouts` plus any `extras` not already among them, resolved to their
    /// current localized names.
    private static func mergeExtras(_ layouts: [Layout], including extras: [String]) -> [Layout] {
        var result = layouts
        var known = Set(result.map(\.id))

        for id in extras where !id.isEmpty && !known.contains(id) {
            known.insert(id)
            result.append(Layout(id: id, name: displayName(forID: id)))
        }
        return result
    }

    /// Alphabetical by name, with the "no layout" row pinned first.
    private static func sortedForPicker(_ layouts: [Layout]) -> [Layout] {
        let none = Constants.Default.noneLanguage
        return layouts.sorted { a, b in
            if a.id == none { return b.id != none }
            if b.id == none { return false }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - Lookup

    /// Input source with this exact id, if it is still installed.
    static func source(forID id: String) -> TISInputSource? {
        KeyboardLayoutUtility.inputSource(forLayout: id)
    }

    /// Localized name for a stored layout id.
    ///
    /// Unknown ids come back unchanged so a layout removed from the system
    /// stays visible instead of turning into an unexplained empty row.
    static func displayName(forID id: String) -> String {
        guard !id.isEmpty, id != Constants.Default.noneLanguage else { return id }
        guard let source = source(forID: id) else { return id }
        return KeyboardLayoutUtility.localizedName(of: source) ?? id
    }
}
