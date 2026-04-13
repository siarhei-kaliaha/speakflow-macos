import AppKit
import Foundation

final class WidgetAnimationController {
    private enum Mode {
        case active
        case processing
    }

    private var animationTimer: Timer?
    private var mode: Mode?
    private var phase: CGFloat = 0
    private var waveformHeightConstraints: [NSLayoutConstraint] = []
    private var waveformBars: [NSView] = []
    private weak var auraView: NSView?
    private let activeBaseHeights: [CGFloat] = [4, 5, 4, 7, 5, 4, 8, 5, 4, 9, 4, 8, 5, 4, 7, 5, 4, 8, 5, 4, 6]
    private let activeSwings: [CGFloat] = [9, 10, 7, 12, 9, 6, 13, 10, 8, 14, 8, 12, 9, 6, 11, 8, 7, 10, 8, 6, 7]
    private let activeOffsets: [CGFloat] = [0.0, 0.31, 0.12, 0.67, 0.22, 0.51, 0.84, 0.43, 0.16, 0.72, 0.28, 0.91, 0.39, 0.14, 0.58, 0.24, 0.47, 0.76, 0.34, 0.18, 0.62]

    func startActive(
        waveformHeightConstraints: [NSLayoutConstraint],
        waveformBars: [NSView],
        auraView: NSView?
    ) {
        configure(
            waveformHeightConstraints: waveformHeightConstraints,
            waveformBars: waveformBars,
            auraView: auraView
        )
        mode = .active
        stop()
        animate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.animate()
        }
    }

    func startProcessing(
        waveformHeightConstraints: [NSLayoutConstraint],
        waveformBars: [NSView],
        auraView: NSView?
    ) {
        configure(
            waveformHeightConstraints: waveformHeightConstraints,
            waveformBars: waveformBars,
            auraView: auraView
        )
        mode = .processing
        stop()
        animate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            self?.animate()
        }
    }

    func reset(waveformHeightConstraints: [NSLayoutConstraint], waveformBars: [NSView], auraView: NSView?) {
        configure(
            waveformHeightConstraints: waveformHeightConstraints,
            waveformBars: waveformBars,
            auraView: auraView
        )
        for (index, constraint) in self.waveformHeightConstraints.enumerated() {
            let fallback = activeBaseHeights[min(index, activeBaseHeights.count - 1)]
            constraint.animator().constant = fallback
        }
        self.waveformBars.forEach { $0.animator().alphaValue = 1.0 }
        auraView?.animator().alphaValue = 0.55
    }

    func stop() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func configure(
        waveformHeightConstraints: [NSLayoutConstraint],
        waveformBars: [NSView],
        auraView: NSView?
    ) {
        self.waveformHeightConstraints = waveformHeightConstraints
        self.waveformBars = waveformBars
        self.auraView = auraView
    }

    private func animate() {
        switch mode {
        case .active:
            animateActiveWaveform()
        case .processing:
            animateProcessingWaveform()
        case .none:
            break
        }
    }

    private func animateActiveWaveform() {
        phase += 0.82
        for index in waveformHeightConstraints.indices {
            let base = activeBaseHeights[min(index, activeBaseHeights.count - 1)]
            let swing = activeSwings[min(index, activeSwings.count - 1)]
            let offset = activeOffsets[min(index, activeOffsets.count - 1)]
            let oscillation = (sin(phase + offset * .pi * 2) + 1) * 0.5
            waveformHeightConstraints[index].animator().constant = base + swing * oscillation
        }

        let auraOpacity = 0.45 + ((sin(phase * 0.8) + 1) * 0.5 * 0.45)
        auraView?.animator().alphaValue = auraOpacity
    }

    private func animateProcessingWaveform() {
        phase += 1
        let step = Int(phase.rounded(.down)) % max(1, waveformHeightConstraints.count)

        for index in waveformHeightConstraints.indices {
            let distance = abs(index - step)
            let height: CGFloat
            switch distance {
            case 0:
                height = 16
            case 1:
                height = 12
            case 2:
                height = 8
            default:
                height = 4
            }
            waveformHeightConstraints[index].animator().constant = height
            waveformBars[index].animator().alphaValue = distance == 0 ? 1.0 : 0.72
        }

        let auraOpacity = 0.24 + (CGFloat((step + 1) % 2) * 0.26)
        auraView?.animator().alphaValue = auraOpacity
    }
}
