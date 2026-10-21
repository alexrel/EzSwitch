import SwiftUI

/// Propagates formatting, stock SwiftUI strings, and RTL direction without an
/// .id(language) reset, which would discard editor state and dismiss sheets.
struct LocalizedContent<Content: View>: View {
    @ObservedObject private var localization = AppLocalization.shared
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.locale, localization.locale)
            .environment(\.layoutDirection, localization.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}
