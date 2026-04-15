import AppKit
import Foundation

final class WaveformStripView: NSView {
    private var configuration = WidgetTheme.waveformGeometry(for: .dictation)
    private var barLayers: [CALayer] = []
    private var levels: [CGFloat] = []
    private var accentColor = WidgetTheme.activeAccent

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: configuration.width, height: configuration.height)
    }

    override func layout() {
        super.layout()
        layoutBars(animated: false)
    }

    func configure(for layoutMode: WidgetWaveformLayoutMode, accentColor: NSColor) {
        configuration = WidgetTheme.waveformGeometry(for: layoutMode)
        self.accentColor = accentColor
        rebuildBarsIfNeeded()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func setAccentColor(_ color: NSColor) {
        accentColor = color
        barLayers.forEach { $0.backgroundColor = color.cgColor }
    }

    func apply(levels: [CGFloat], animated: Bool) {
        self.levels = normalizedLevels(from: levels, count: configuration.barCount)
        layoutBars(animated: animated)
    }

    private func rebuildBarsIfNeeded() {
        guard barLayers.count != configuration.barCount else {
            barLayers.forEach { $0.backgroundColor = accentColor.cgColor }
            return
        }

        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        barLayers = (0..<configuration.barCount).map { _ in
            let barLayer = CALayer()
            barLayer.cornerRadius = configuration.barCornerRadius
            barLayer.cornerCurve = .continuous
            barLayer.backgroundColor = accentColor.cgColor
            layer?.addSublayer(barLayer)
            return barLayer
        }
        levels = Array(repeating: 0, count: configuration.barCount)
    }

    private func layoutBars(animated: Bool) {
        guard !barLayers.isEmpty else { return }

        let resolvedLevels = normalizedLevels(from: levels, count: configuration.barCount)
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(animated ? 0.12 : 0.0)

        for (index, barLayer) in barLayers.enumerated() {
            let level = max(0, min(1, resolvedLevels[index]))
            let height = configuration.minBarHeight + ((configuration.maxBarHeight - configuration.minBarHeight) * level)
            let x = CGFloat(index) * (configuration.barWidth + configuration.barGap)
            let y = (bounds.height - height) * 0.5
            barLayer.frame = CGRect(x: x, y: y, width: configuration.barWidth, height: height)
            barLayer.opacity = Float(0.68 + (0.32 * level))
        }

        CATransaction.commit()
    }

    private func normalizedLevels(from incoming: [CGFloat], count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        if incoming.count == count { return incoming }
        if incoming.isEmpty { return Array(repeating: 0, count: count) }

        if incoming.count > count {
            let stride = CGFloat(incoming.count) / CGFloat(count)
            return (0..<count).map { index in
                let mappedIndex = min(incoming.count - 1, Int((CGFloat(index) * stride).rounded(.down)))
                return incoming[mappedIndex]
            }
        }

        return incoming + Array(repeating: 0, count: count - incoming.count)
    }
}
