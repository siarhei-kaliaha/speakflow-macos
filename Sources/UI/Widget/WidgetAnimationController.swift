import AppKit
import Foundation

final class WidgetAnimationController {
    private var animationTimer: Timer?
    private var equalizerPhase: CGFloat = 0
    private var processingPhase = 0
    private var barHeightConstraints: [NSLayoutConstraint] = []
    private var processingDotSizeConstraints: [NSLayoutConstraint] = []
    private var processingDots: [NSView] = []

    func startEqualizer(
        barHeightConstraints: [NSLayoutConstraint],
        processingDotSizeConstraints: [NSLayoutConstraint],
        processingDots: [NSView]
    ) {
        configure(
            barHeightConstraints: barHeightConstraints,
            processingDotSizeConstraints: processingDotSizeConstraints,
            processingDots: processingDots
        )

        guard animationTimer == nil else { return }
        animateBars()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.11, repeats: true) { [weak self] _ in
            self?.animateBars()
        }
    }

    func startProcessing(
        barHeightConstraints: [NSLayoutConstraint],
        processingDotSizeConstraints: [NSLayoutConstraint],
        processingDots: [NSView]
    ) {
        configure(
            barHeightConstraints: barHeightConstraints,
            processingDotSizeConstraints: processingDotSizeConstraints,
            processingDots: processingDots
        )
        stop()
        animateProcessingDots()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.24, repeats: true) { [weak self] _ in
            self?.animateProcessingDots()
        }
    }

    func reset(
        barHeightConstraints: [NSLayoutConstraint],
        processingDotSizeConstraints: [NSLayoutConstraint],
        processingDots: [NSView]
    ) {
        configure(
            barHeightConstraints: barHeightConstraints,
            processingDotSizeConstraints: processingDotSizeConstraints,
            processingDots: processingDots
        )
        let heights: [CGFloat] = [7.0, 13.0, 7.0]
        for (constraint, value) in zip(self.barHeightConstraints, heights) {
            constraint.animator().constant = value
        }
        for (index, constraint) in self.processingDotSizeConstraints.enumerated() {
            constraint.animator().constant = index == 1 ? 7.0 : 5.0
            self.processingDots[index].animator().alphaValue = index == 1 ? 1.0 : 0.55
        }
    }

    func stop() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func configure(
        barHeightConstraints: [NSLayoutConstraint],
        processingDotSizeConstraints: [NSLayoutConstraint],
        processingDots: [NSView]
    ) {
        self.barHeightConstraints = barHeightConstraints
        self.processingDotSizeConstraints = processingDotSizeConstraints
        self.processingDots = processingDots
    }

    private func animateBars() {
        equalizerPhase += 0.65
        for (index, constraint) in barHeightConstraints.enumerated() {
            let distance = abs(index - 1)
            let base: CGFloat
            let swing: CGFloat
            let phaseOffset = CGFloat(distance) * 0.72
            switch distance {
            case 0:
                base = 11.0
                swing = 3.2
            default:
                base = 7.2
                swing = 2.0
            }
            let oscillation = (sin(equalizerPhase + phaseOffset) + 1) * 0.5
            constraint.animator().constant = base + swing * oscillation
        }
    }

    private func animateProcessingDots() {
        guard !processingDots.isEmpty else { return }
        processingPhase = (processingPhase + 1) % processingDots.count
        for (index, constraint) in processingDotSizeConstraints.enumerated() {
            let isFocused = index == processingPhase
            constraint.animator().constant = isFocused ? 8.0 : 5.0
            processingDots[index].animator().alphaValue = isFocused ? 1.0 : 0.45
        }
    }
}
