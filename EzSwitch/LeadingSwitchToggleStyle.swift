import SwiftUI

/// Keeps native switch behavior while aligning controls before their labels.
struct LeadingSwitchToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .fixedSize()

            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(isEnabled ? Color.primary : .secondary)
                .accessibilityHidden(true)
                .onTapGesture {
                    if isEnabled { configuration.isOn.toggle() }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
