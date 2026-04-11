import AppKit
import Foundation
final class WidgetContentView: NSView {
    var onToggle: (() -> Void)?

    enum VisualState {
        case idle
        case active
        case processing
    }

    private let capsuleView = NSVisualEffectView()
    private let borderView = NSView()
    private let glowView = NSView()
    private let idleLineView = NSView()
    private let equalizerContainer = NSView()
    private let equalizerStack = NSStackView()
    private let barViews = (0 ..< 3).map { _ in NSView() }
    private let processingStack = NSStackView()
    private let processingDots = (0 ..< 3).map { _ in NSView() }
    private let backgroundGradientLayer = CAGradientLayer()
    private let sheenLayer = CAGradientLayer()
    private var barHeightConstraints: [NSLayoutConstraint] = []
    private var processingDotSizeConstraints: [NSLayoutConstraint] = []
    private var animationTimer: Timer?
    private var visualState: VisualState = .idle
    private var trackingAreaRef: NSTrackingArea?
    private var isHovered = false
    private var processingPhase = 0
    private var equalizerPhase: CGFloat = 0
    private var idleLineWidthConstraint: NSLayoutConstraint?
    private var glowWidthConstraint: NSLayoutConstraint?
    private var glowHeightConstraint: NSLayoutConstraint?

    private var dragStartMouseLocation = NSPoint.zero
    private var dragStartWindowOrigin = NSPoint.zero
    private var didDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    override var isFlipped: Bool {
        true
    }

    private func setupView() {
        wantsLayer = true

        capsuleView.translatesAutoresizingMaskIntoConstraints = false
        capsuleView.material = .hudWindow
        capsuleView.blendingMode = .withinWindow
        capsuleView.state = .active
        capsuleView.wantsLayer = true
        capsuleView.layer?.cornerRadius = 13
        capsuleView.layer?.cornerCurve = .continuous
        capsuleView.layer?.masksToBounds = true
        capsuleView.layer?.backgroundColor = NSColor.clear.cgColor

        backgroundGradientLayer.colors = [
            NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.07, alpha: 0.96).cgColor,
            NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 0.98).cgColor
        ]
        backgroundGradientLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        backgroundGradientLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        backgroundGradientLayer.cornerRadius = 13
        backgroundGradientLayer.cornerCurve = .continuous
        capsuleView.layer?.addSublayer(backgroundGradientLayer)

        sheenLayer.colors = [
            NSColor.white.withAlphaComponent(0.10).cgColor,
            NSColor.white.withAlphaComponent(0.01).cgColor
        ]
        sheenLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        sheenLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        sheenLayer.cornerRadius = 13
        sheenLayer.cornerCurve = .continuous
        capsuleView.layer?.addSublayer(sheenLayer)

        borderView.translatesAutoresizingMaskIntoConstraints = false
        borderView.wantsLayer = true
        borderView.layer?.cornerRadius = 13
        borderView.layer?.cornerCurve = .continuous
        borderView.layer?.borderWidth = 0.7
        borderView.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        borderView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.015).cgColor

        glowView.translatesAutoresizingMaskIntoConstraints = false
        glowView.wantsLayer = true
        glowView.layer?.cornerRadius = 7
        glowView.layer?.cornerCurve = .continuous
        glowView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.03).cgColor

        idleLineView.translatesAutoresizingMaskIntoConstraints = false
        idleLineView.wantsLayer = true
        idleLineView.layer?.cornerRadius = 2
        idleLineView.layer?.cornerCurve = .continuous
        idleLineView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.96).cgColor

        equalizerStack.translatesAutoresizingMaskIntoConstraints = false
        equalizerStack.orientation = .horizontal
        equalizerStack.alignment = .centerY
        equalizerStack.distribution = .fill
        equalizerStack.spacing = 6.0

        equalizerContainer.translatesAutoresizingMaskIntoConstraints = false
        processingStack.translatesAutoresizingMaskIntoConstraints = false
        processingStack.orientation = .horizontal
        processingStack.alignment = .centerY
        processingStack.distribution = .fillEqually
        processingStack.spacing = 4

        for bar in barViews {
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.wantsLayer = true
            bar.layer?.cornerRadius = 1.8
            bar.layer?.cornerCurve = .continuous
            bar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.96).cgColor
            equalizerStack.addArrangedSubview(bar)

            let width = bar.widthAnchor.constraint(equalToConstant: 6.0)
            let height = bar.heightAnchor.constraint(equalToConstant: 10.0)
            width.isActive = true
            height.isActive = true
            barHeightConstraints.append(height)
        }

        for dot in processingDots {
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3
            dot.layer?.cornerCurve = .continuous
            dot.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
            processingStack.addArrangedSubview(dot)

            let width = dot.widthAnchor.constraint(equalToConstant: 6)
            let height = dot.heightAnchor.constraint(equalToConstant: 6)
            width.isActive = true
            height.isActive = true
            processingDotSizeConstraints.append(width)
        }

        addSubview(capsuleView)
        capsuleView.addSubview(borderView)
        capsuleView.addSubview(glowView)
        capsuleView.addSubview(idleLineView)
        capsuleView.addSubview(equalizerContainer)
        equalizerContainer.addSubview(equalizerStack)
        capsuleView.addSubview(processingStack)

        let glowWidthConstraint = glowView.widthAnchor.constraint(equalToConstant: 44)
        let glowHeightConstraint = glowView.heightAnchor.constraint(equalToConstant: 14)
        let idleLineWidthConstraint = idleLineView.widthAnchor.constraint(equalToConstant: 96)
        self.glowWidthConstraint = glowWidthConstraint
        self.glowHeightConstraint = glowHeightConstraint
        self.idleLineWidthConstraint = idleLineWidthConstraint

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: widgetOuterSize.width),
            heightAnchor.constraint(equalToConstant: widgetOuterSize.height),

            capsuleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            capsuleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            capsuleView.widthAnchor.constraint(equalToConstant: widgetCapsuleSize.width),
            capsuleView.heightAnchor.constraint(equalToConstant: widgetCapsuleSize.height),

            borderView.leadingAnchor.constraint(equalTo: capsuleView.leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: capsuleView.trailingAnchor),
            borderView.topAnchor.constraint(equalTo: capsuleView.topAnchor),
            borderView.bottomAnchor.constraint(equalTo: capsuleView.bottomAnchor),

            glowView.centerXAnchor.constraint(equalTo: capsuleView.centerXAnchor),
            glowView.centerYAnchor.constraint(equalTo: capsuleView.centerYAnchor),
            glowWidthConstraint,
            glowHeightConstraint,

            idleLineView.centerXAnchor.constraint(equalTo: capsuleView.centerXAnchor),
            idleLineView.centerYAnchor.constraint(equalTo: capsuleView.centerYAnchor),
            idleLineWidthConstraint,
            idleLineView.heightAnchor.constraint(equalToConstant: 4),

            equalizerContainer.centerXAnchor.constraint(equalTo: capsuleView.centerXAnchor),
            equalizerContainer.centerYAnchor.constraint(equalTo: capsuleView.centerYAnchor),
            equalizerContainer.widthAnchor.constraint(equalToConstant: 30),
            equalizerContainer.heightAnchor.constraint(equalToConstant: 16),

            equalizerStack.leadingAnchor.constraint(equalTo: equalizerContainer.leadingAnchor),
            equalizerStack.trailingAnchor.constraint(equalTo: equalizerContainer.trailingAnchor),
            equalizerStack.centerYAnchor.constraint(equalTo: equalizerContainer.centerYAnchor),
            equalizerStack.heightAnchor.constraint(equalToConstant: 14),

            processingStack.centerXAnchor.constraint(equalTo: capsuleView.centerXAnchor),
            processingStack.centerYAnchor.constraint(equalTo: capsuleView.centerYAnchor),
            processingStack.widthAnchor.constraint(equalToConstant: 40),
            processingStack.heightAnchor.constraint(equalToConstant: 10)
        ])

        apply(state: .idle)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaRef = tracking
    }

    override func layout() {
        super.layout()
        backgroundGradientLayer.frame = capsuleView.bounds
        sheenLayer.frame = capsuleView.bounds
    }

    func apply(state: VisualState) {
        visualState = state
        renderVisualState()
    }

    private func renderVisualState() {
        switch visualState {
        case .idle:
            equalizerContainer.isHidden = true
            processingStack.isHidden = true
            idleLineView.isHidden = false
            glowView.layer?.backgroundColor = NSColor.white.withAlphaComponent(isHovered ? 0.05 : 0.024).cgColor
            borderView.layer?.borderColor = NSColor.white.withAlphaComponent(isHovered ? 0.18 : 0.11).cgColor
            borderView.layer?.borderWidth = 0.7
            capsuleView.animator().alphaValue = isHovered ? 1.0 : 0.94
            idleLineWidthConstraint?.animator().constant = isHovered ? 108 : 96
            glowWidthConstraint?.animator().constant = isHovered ? 54 : 44
            glowHeightConstraint?.animator().constant = isHovered ? 16 : 14
            stopAnimation()
        case .active:
            equalizerContainer.isHidden = false
            processingStack.isHidden = true
            idleLineView.isHidden = true
            glowView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            borderView.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
            borderView.layer?.borderWidth = 0.7
            capsuleView.animator().alphaValue = 1.0
            glowWidthConstraint?.animator().constant = 48
            glowHeightConstraint?.animator().constant = 15
            startEqualizerAnimation()
        case .processing:
            equalizerContainer.isHidden = true
            processingStack.isHidden = false
            idleLineView.isHidden = true
            glowView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.045).cgColor
            borderView.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
            borderView.layer?.borderWidth = 0.7
            capsuleView.animator().alphaValue = 0.98
            glowWidthConstraint?.animator().constant = 46
            glowHeightConstraint?.animator().constant = 15
            startProcessingAnimation()
        }
    }

    private func startEqualizerAnimation() {
        guard animationTimer == nil else { return }
        animateBars()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.11, repeats: true) { [weak self] _ in
            self?.animateBars()
        }
    }

    private func startProcessingAnimation() {
        stopAnimation()
        animateProcessingDots()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.24, repeats: true) { [weak self] _ in
            self?.animateProcessingDots()
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        let heights: [CGFloat] = [7.0, 13.0, 7.0]
        for (constraint, value) in zip(barHeightConstraints, heights) {
            constraint.animator().constant = value
        }
        for (index, constraint) in processingDotSizeConstraints.enumerated() {
            constraint.animator().constant = index == 1 ? 7.0 : 5.0
            processingDots[index].animator().alphaValue = index == 1 ? 1.0 : 0.55
        }
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
        processingPhase = (processingPhase + 1) % processingDots.count
        for (index, constraint) in processingDotSizeConstraints.enumerated() {
            let isFocused = index == processingPhase
            constraint.animator().constant = isFocused ? 8.0 : 5.0
            processingDots[index].animator().alphaValue = isFocused ? 1.0 : 0.45
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        if visualState == .idle {
            renderVisualState()
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if visualState == .idle {
            renderVisualState()
        }
    }

    override func mouseDown(with event: NSEvent) {
        didDrag = false
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }

        let current = NSEvent.mouseLocation
        let deltaX = current.x - dragStartMouseLocation.x
        let deltaY = current.y - dragStartMouseLocation.y
        if abs(deltaX) > 2 || abs(deltaY) > 2 {
            didDrag = true
        }

        let nextOrigin = NSPoint(x: dragStartWindowOrigin.x + deltaX, y: dragStartWindowOrigin.y + deltaY)
        window.setFrameOrigin(nextOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        guard window != nil else { return }
        if didDrag {
        } else {
            onToggle?()
        }
    }
}

final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

