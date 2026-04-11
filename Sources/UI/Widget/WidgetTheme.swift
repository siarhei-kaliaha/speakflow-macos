import AppKit
import Foundation

enum WidgetTheme {
    static let widgetOuterSize = NSSize(width: 184, height: 42)
    static let widgetCapsuleSize = NSSize(width: 160, height: 28)

    static let capsuleCornerRadius: CGFloat = 13
    static let borderWidth: CGFloat = 0.7
    static let borderFill = NSColor.white.withAlphaComponent(0.015)
    static let idleAlpha: CGFloat = 0.94
    static let processingAlpha: CGFloat = 0.98

    static let glowCornerRadius: CGFloat = 7
    static let idleLineCornerRadius: CGFloat = 2
    static let equalizerBarCornerRadius: CGFloat = 1.8
    static let processingDotRestSize: CGFloat = 5

    static let glowRestWidth: CGFloat = 44
    static let glowHoverWidth: CGFloat = 54
    static let glowRestHeight: CGFloat = 14
    static let glowHoverHeight: CGFloat = 16
    static let activeGlowWidth: CGFloat = 48
    static let activeGlowHeight: CGFloat = 15
    static let processingGlowWidth: CGFloat = 46
    static let processingGlowHeight: CGFloat = 15

    static let idleLineRestWidth: CGFloat = 96
    static let idleLineHoverWidth: CGFloat = 108
    static let idleLineHeight: CGFloat = 4

    static let equalizerWidth: CGFloat = 34
    static let equalizerHeight: CGFloat = 16
    static let equalizerStackHeight: CGFloat = 14
    static let equalizerSpacing: CGFloat = 6
    static let equalizerBarWidth: CGFloat = 6
    static let equalizerBarRestHeight: CGFloat = 7

    static let processingWidth: CGFloat = 40
    static let processingHeight: CGFloat = 10
    static let processingSpacing: CGFloat = 4
    static let processingDotColor = NSColor.white.withAlphaComponent(0.92)

    static let dragThreshold: CGFloat = 2

    static let backgroundGradientColors: [CGColor] = [
        NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.07, alpha: 0.96).cgColor,
        NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 0.98).cgColor
    ]

    static let sheenGradientColors: [CGColor] = [
        NSColor.white.withAlphaComponent(0.10).cgColor,
        NSColor.white.withAlphaComponent(0.01).cgColor
    ]

    static let processingGlowColor = NSColor.white.withAlphaComponent(0.045)
    static let primaryForeground = NSColor.white.withAlphaComponent(0.96)

    static func borderColor(for state: WidgetContentView.VisualState, hovered: Bool) -> NSColor {
        switch state {
        case .idle:
            return NSColor.white.withAlphaComponent(hovered ? 0.18 : 0.11)
        case .active:
            return NSColor.white.withAlphaComponent(0.14)
        case .processing:
            return NSColor.white.withAlphaComponent(0.16)
        }
    }

    static func glowColor(hovered: Bool) -> NSColor {
        NSColor.white.withAlphaComponent(hovered ? 0.05 : 0.024)
    }
}
