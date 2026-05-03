import AppKit
import Foundation

enum WidgetWaveformLayoutMode {
    case dictation
    case recording
    case processing
}

struct WidgetWaveformGeometry {
    let width: CGFloat
    let height: CGFloat
    let barCount: Int
    let barWidth: CGFloat
    let barGap: CGFloat
    let minBarHeight: CGFloat
    let maxBarHeight: CGFloat
    let barCornerRadius: CGFloat
}

enum WidgetTheme {
    static let compactWidgetOuterSize = NSSize(width: 164, height: 40)
    static let compactWidgetCapsuleSize = NSSize(width: 156, height: 32)
    static let meetingWidgetOuterSize = NSSize(width: 258, height: 52)
    static let meetingWidgetCapsuleSize = NSSize(width: 250, height: 44)

    static let capsuleCornerRadius: CGFloat = 16
    static let meetingCapsuleCornerRadius: CGFloat = 22
    static let borderWidth: CGFloat = 1
    static let idleAlpha: CGFloat = 0.96
    static let activeAlpha: CGFloat = 1.0
    static let processingAlpha: CGFloat = 1.0

    static let glowCornerRadius: CGFloat = 8
    static let idleTrackCornerRadius: CGFloat = 4
    static let idleIndicatorCornerRadius: CGFloat = 1.5
    static let stopButtonSize: CGFloat = 18
    static let stopButtonCornerRadius: CGFloat = 9
    static let stopButtonSlotWidth: CGFloat = 24
    static let timerSlotWidth: CGFloat = 40
    static let meetingButtonSize: CGFloat = 26
    static let meetingButtonCornerRadius: CGFloat = 13

    static let idleGlowRestWidth: CGFloat = 56
    static let idleGlowHoverWidth: CGFloat = 62
    static let idleGlowRestHeight: CGFloat = 10
    static let idleGlowHoverHeight: CGFloat = 12

    static let idleTrackWidth: CGFloat = 80
    static let idleTrackHeight: CGFloat = 8
    static let idleIndicatorRestWidth: CGFloat = 68
    static let idleIndicatorHoverWidth: CGFloat = 74
    static let idleIndicatorHeight: CGFloat = 3

    static let contentHorizontalInset: CGFloat = 10
    static let contentSpacing: CGFloat = 8
    static let meetingContentHorizontalInset: CGFloat = 22
    static let meetingTextLeadingInset: CGFloat = 2
    static let waveformLaneHeight: CGFloat = 18
    static let waveformBarWidth: CGFloat = 2
    static let waveformBarGap: CGFloat = 2
    static let waveformMinBarHeight: CGFloat = 4
    static let waveformMaxBarHeight: CGFloat = 14
    static let timerFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
    static let timerColor = NSColor.white.withAlphaComponent(0.96)
    static let stopButtonFill = NSColor.white.withAlphaComponent(0.08)
    static let stopButtonBorder = NSColor.white.withAlphaComponent(0.12)
    static let stopButtonSymbol = NSColor.white.withAlphaComponent(0.88)
    static let meetingEyebrowFont = NSFont.systemFont(ofSize: 10, weight: .medium)
    static let meetingTitleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let meetingEyebrowColor = NSColor(calibratedRed: 0.631, green: 0.631, blue: 0.667, alpha: 1.0)
    static let meetingTitleColor = NSColor.white
    static let meetingButtonFill = NSColor.white.withAlphaComponent(0.04)
    static let meetingButtonBorder = NSColor.white.withAlphaComponent(0.12)
    static let meetingDismissSymbol = NSColor(calibratedRed: 0.631, green: 0.631, blue: 0.667, alpha: 1.0)
    static let meetingRecordDot = NSColor(calibratedRed: 0.957, green: 0.247, blue: 0.369, alpha: 1.0)

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
        NSColor.white.withAlphaComponent(0.05).cgColor,
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

    static func widgetOuterSize(for state: WidgetContentView.VisualState) -> NSSize {
        switch state {
        case .meetingDetected:
            return meetingWidgetOuterSize
        default:
            return compactWidgetOuterSize
        }
    }

    static func widgetCapsuleSize(for state: WidgetContentView.VisualState) -> NSSize {
        switch state {
        case .meetingDetected:
            return meetingWidgetCapsuleSize
        default:
            return compactWidgetCapsuleSize
        }
    }

    static func capsuleCornerRadius(for state: WidgetContentView.VisualState) -> CGFloat {
        switch state {
        case .meetingDetected:
            return meetingCapsuleCornerRadius
        default:
            return capsuleCornerRadius
        }
    }

    static func waveformGeometry(for mode: WidgetWaveformLayoutMode) -> WidgetWaveformGeometry {
        let contentInnerWidth = compactWidgetCapsuleSize.width - (contentHorizontalInset * 2)
        let usableWidth: CGFloat
        switch mode {
        case .dictation, .processing:
            usableWidth = contentInnerWidth - timerSlotWidth - contentSpacing
        case .recording:
            usableWidth = contentInnerWidth - stopButtonSlotWidth - timerSlotWidth - (contentSpacing * 2)
        }

        let barCount = max(8, Int(floor((usableWidth + waveformBarGap) / (waveformBarWidth + waveformBarGap))))
        let resolvedWidth = CGFloat(barCount) * waveformBarWidth + CGFloat(max(0, barCount - 1)) * waveformBarGap
        return WidgetWaveformGeometry(
            width: resolvedWidth,
            height: waveformLaneHeight,
            barCount: barCount,
            barWidth: waveformBarWidth,
            barGap: waveformBarGap,
            minBarHeight: waveformMinBarHeight,
            maxBarHeight: waveformMaxBarHeight,
            barCornerRadius: 1.25
        )
    }

    static func borderColor(for state: WidgetContentView.VisualState, hovered: Bool) -> NSColor {
        switch state {
        case .idle:
            return NSColor(calibratedWhite: hovered ? 0.33 : 0.24, alpha: hovered ? 0.72 : 0.58)
        case .dictationActive, .recordingActive:
            return NSColor(calibratedWhite: 0.28, alpha: 0.72)
        case .meetingDetected:
            return NSColor(calibratedWhite: 0.30, alpha: 0.74)
        case .processingDictation, .processingRecording:
            return NSColor(calibratedWhite: 0.30, alpha: 0.74)
        }
    }

    static func glowColor(hovered: Bool) -> NSColor {
        hovered ? hoverGlowColor : idleGlowColor
    }
}
