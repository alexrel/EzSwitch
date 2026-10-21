import SwiftUI
import AppKit

/// Keeps the native popup and menu, while aligning its selected value to the
/// interface's leading edge even when AppKit retains launch-time alignment.
struct SettingsPicker<Selection: Hashable>: View {
    let title: String
    @Binding var selection: Selection
    let options: [(value: Selection, title: String)]
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, selection: Binding<Selection>, options: [(value: Selection, title: String)]) {
        self.title = title
        _selection = selection
        self.options = options
    }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options.indices, id: \.self) { index in
                Text(verbatim: options[index].title).tag(options[index].value)
            }
        }
        .labelsHidden()
        // Rebuild only the native popup when its arrow must change sides.
        // The binding and the surrounding editor keep their existing state.
        .id(layoutDirection == .rightToLeft)
        // Compact popups must also reserve the space used by the RTL title overlay.
        .frame(idealWidth: layoutDirection == .rightToLeft ? rtlIdealWidth : nil)
        .overlay {
            if layoutDirection == .rightToLeft {
                // Replace only the collapsed title area. The native border,
                // arrow, menu, hit testing, and accessible value stay intact.
                Text(verbatim: options.first(where: { $0.value == selection })?.title ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(isEnabled ? Color.primary : Color(NSColor.disabledControlTextColor))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .padding(.vertical, 3)
                    .padding(.leading, 3)
                    .padding(.trailing, 22)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var rtlIdealWidth: CGFloat {
        let title = options.first(where: { $0.value == selection })?.title ?? ""
        let textWidth = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
        return ceil(textWidth) + 36
    }
}
