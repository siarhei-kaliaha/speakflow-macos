import AppKit
import Foundation

enum WidgetTheme {
    static let widgetOuterSize = NSSize(width: 164, height: 40)
    static let widgetCapsuleSize = NSSize(width: 156, height: 32)

    static let capsuleCornerRadius: CGFloat = 16
    static let borderWidth: CGFloat = 1
    static let idleAlpha: CGFloat = 0.96
    static let activeAlpha: CGFloat = 1.0
    static let processingAlpha: CGFloat = 1.0

    static let glowCornerRadius: CGFloat = 8
    static let idleTrackCornerRadius: CGFloat = 4
    static let idleIndicatorCornerRadius: CGFloat = 1.5
    static let waveformBarWidth: CGFloat = 2.0
    static let waveformBarCornerRadius: CGFloat = 1.25

    static let idleGlowRestWidth: CGFloat = 56
    static let idleGlowHoverWidth: CGFloat = 62
    static let idleGlowRestHeight: CGFloat = 10
    static let idleGlowHoverHeight: CGFloat = 12

    static let idleTrackWidth: CGFloat = 80
    static let idleTrackHeight: CGFloat = 8
    static let idleIndicatorRestWidth: CGFloat = 68
    static let idleIndicatorHoverWidth: CGFloat = 74
    static let idleIndicatorHeight: CGFloat = 3

    static let waveformWidth: CGFloat = 98
    static let waveformHeight: CGFloat = 18
    static let waveformSpacing: CGFloat = 2.0
    static let contentHorizontalInset: CGFloat = 10
    static let contentSpacing: CGFloat = 8
    static let timerWidth: CGFloat = 30
    static let timerFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
    static let timerColor = NSColor.white.withAlphaComponent(0.96)

    static let dragThreshold: CGFloat = 2

    static let backgroundGradientColors: [CGColor] = [
        NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.21, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.12, alpha: 1.0).cgColor
    ]

    static let idleTrackGradientColors: [CGColor] = [
        NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.21, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.09, alpha: 1.0).cgColor
    ]

    static let topSheenGradientColors: [CGColor] = [
        NSColor.white.withAlphaComponent(0.07).cgColor,
        NSColor.white.withAlphaComponent(0.0).cgColor
    ]

    static let idleStandbyGradientColors: [CGColor] = [
        NSColor(calibratedWhite: 0.35, alpha: 0.18).cgColor,
        NSColor(calibratedWhite: 0.52, alpha: 0.82).cgColor,
        NSColor(calibratedWhite: 0.35, alpha: 0.18).cgColor
    ]

    static let capsuleFill = NSColor.black.withAlphaComponent(0.18)
    static let idleTrackBorder = NSColor.white.withAlphaComponent(0.11)
    static let idleTrackShadow = NSColor.black.withAlphaComponent(0.58)
    static let idleGlowColor = NSColor.white.withAlphaComponent(0.012)
    static let hoverGlowColor = NSColor.white.withAlphaComponent(0.028)

    static let activeAccent = NSColor(calibratedRed: 1.0, green: 0.165, blue: 0.373, alpha: 1.0)
    static let processingAccent = NSColor(calibratedRed: 0.0, green: 0.898, blue: 1.0, alpha: 1.0)

    static func borderColor(for state: WidgetContentView.VisualState, hovered: Bool) -> NSColor {
        switch state {
        case .idle:
            return NSColor(calibratedWhite: hovered ? 0.33 : 0.24, alpha: hovered ? 0.72 : 0.58)
        case .active:
            return NSColor(calibratedWhite: 0.28, alpha: 0.72)
        case .processing:
            return NSColor(calibratedWhite: 0.30, alpha: 0.74)
        }
    }

    static func glowColor(hovered: Bool) -> NSColor {
        hovered ? hoverGlowColor : idleGlowColor
    }
}
