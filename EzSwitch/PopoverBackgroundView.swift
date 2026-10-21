import AppKit

/// One native surface covers both the popover body and its arrow.
final class PopoverBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let start = dark
            ? NSColor(srgbRed: 0.16, green: 0.18, blue: 0.23, alpha: 1)
            : NSColor(srgbRed: 0.93, green: 0.95, blue: 1.0, alpha: 1)
        let end = dark
            ? NSColor(srgbRed: 0.12, green: 0.13, blue: 0.17, alpha: 1)
            : NSColor(srgbRed: 0.96, green: 0.97, blue: 0.99, alpha: 1)
        let rtl = AppLocalization.shared.isRightToLeft
        NSGradient(starting: start, ending: end)?.draw(
            from: NSPoint(x: rtl ? bounds.maxX : bounds.minX, y: bounds.maxY),
            to: NSPoint(x: rtl ? bounds.minX : bounds.maxX, y: bounds.minY),
            options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation]
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
