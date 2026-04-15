import AppKit
import Foundation

final class WidgetAnimationController {
    private var animationTimer: Timer?
    private var phase: Int = 0
    private var barCount = 0
    private var onFrame: (([CGFloat]) -> Void)?

    func startProcessing(barCount: Int, onFrame: @escaping ([CGFloat]) -> Void) {
        stop()
        self.barCount = barCount
        self.onFrame = onFrame
        emitProcessingFrame()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in
            self?.emitProcessingFrame()
        }
    }

    func stop() {
        animationTimer?.invalidate()
        animationTimer = nil
        onFrame = nil
        phase = 0
    }

    private func emitProcessingFrame() {
        guard barCount > 0 else { return }
        let index = phase % barCount
        let levels = (0..<barCount).map { currentIndex -> CGFloat in
            let distance = abs(currentIndex - index)
            switch distance {
            case 0:
                return 1.0
            case 1:
                return 0.72
            case 2:
                return 0.42
            default:
                return 0.08
            }
        }
        onFrame?(levels)
        phase += 1
    }
}
