import AppKit
import Foundation

final class WidgetContentView: NSView {
    enum VisualState {
        case idle
        case active
        case processing
    }

    var onToggle: (() -> Void)?

    private let capsuleView = NSVisualEffectView()
    private let borderView = NSView()
    private let glowView = NSView()
    private let idleLineView = NSView()
    private let equalizerContainer = NSView()
    private let equalizerStack = NSStackView()
    private let barViews = (0..<3).map { _ in NSView() }
    private let processingStack = NSStackView()
    private let processingDots = (0..<3).map { _ in NSView() }
    private let backgroundGradientLayer = CAGradientLayer()
    private let sheenLayer = CAGradientLayer()
    private let animationController = WidgetAnimationController()

    private var barHeightConstraints: [NSLayoutConstraint] = []
    private var processingDotSizeConstraints: [NSLayoutConstraint] = []
    private var trackingAreaRef: NSTrackingArea?
    private var visualState: VisualState = .idle
    private var isHovered = false

    private var idleLineWidthConstraint: NSLayoutConstraint?
    private var glowWidthConstraint: NSLayoutConstraint?
    private var glowHeightConstraint: NSLayoutConstraint?

    private var dragStartMouseLocation = NSPoint.zero
    private var dragStartWindowOrigin = NSPoint.zero
    private var didDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildWidget()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildWidget()
    }

    override var isFlipped: Bool { true }

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

    private func buildWidget() {
        wantsLayer = true
        configureShell()
        configureSubhierarchy()
        configureConstraints()
        apply(state: .idle)
    }

    private func configureShell() {
        capsuleView.translatesAutoresizingMaskIntoConstraints = false
        capsuleView.material = .hudWindow
        capsuleView.blendingMode = .withinWindow
        capsuleView.state = .active
        capsuleView.wantsLayer = true
        capsuleView.layer?.cornerRadius = WidgetTheme.capsuleCornerRadius
        capsuleView.layer?.cornerCurve = .continuous
        capsuleView.layer?.masksToBounds = true
        capsuleView.layer?.backgroundColor = NSColor.clear.cgColor

        backgroundGradientLayer.colors = WidgetTheme.backgroundGradientColors
        backgroundGradientLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        backgroundGradientLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        backgroundGradientLayer.cornerRadius = WidgetTheme.capsuleCornerRadius
        backgroundGradientLayer.cornerCurve = .continuous
        capsuleView.layer?.addSublayer(backgroundGradientLayer)

        sheenLayer.colors = WidgetTheme.sheenGradientColors
        sheenLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        sheenLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        sheenLayer.cornerRadius = WidgetTheme.capsuleCornerRadius
        sheenLayer.cornerCurve = .continuous
        capsuleView.layer?.addSublayer(sheenLayer)
    }

    private func configureSubhierarchy() {
        configureBorder()
        configureGlow()
        configureIdleLine()
        configureEqualizer()
        configureProcessingIndicator()

        addSubview(capsuleView)
        capsuleView.addSubview(borderView)
        capsuleView.addSubview(glowView)
        capsuleView.addSubview(idleLineView)
        capsuleView.addSubview(equalizerContainer)
        equalizerContainer.addSubview(equalizerStack)
        capsuleView.addSubview(processingStack)
    }

    private func configureBorder() {
        borderView.translatesAutoresizingMaskIntoConstraints = false
        borderView.wantsLayer = true
        borderView.layer?.cornerRadius = WidgetTheme.capsuleCornerRadius
        borderView.layer?.cornerCurve = .continuous
        borderView.layer?.borderWidth = WidgetTheme.borderWidth
        borderView.layer?.borderColor = WidgetTheme.borderColor(for: .idle, hovered: false).cgColor
        borderView.layer?.backgroundColor = WidgetTheme.borderFill.cgColor
    }

    private func configureGlow() {
        glowView.translatesAutoresizingMaskIntoConstraints = false
        glowView.wantsLayer = true
        glowView.layer?.cornerRadius = WidgetTheme.glowCornerRadius
        glowView.layer?.cornerCurve = .continuous
        glowView.layer?.backgroundColor = WidgetTheme.glowColor(hovered: false).cgColor
    }

    private func configureIdleLine() {
        idleLineView.translatesAutoresizingMaskIntoConstraints = false
        idleLineView.wantsLayer = true
        idleLineView.layer?.cornerRadius = WidgetTheme.idleLineCornerRadius
        idleLineView.layer?.cornerCurve = .continuous
        idleLineView.layer?.backgroundColor = WidgetTheme.primaryForeground.cgColor
    }

    private func configureEqualizer() {
        equalizerStack.translatesAutoresizingMaskIntoConstraints = false
        equalizerStack.orientation = .horizontal
        equalizerStack.alignment = .centerY
        equalizerStack.distribution = .fill
        equalizerStack.spacing = WidgetTheme.equalizerSpacing

        equalizerContainer.translatesAutoresizingMaskIntoConstraints = false

        for bar in barViews {
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.wantsLayer = true
            bar.layer?.cornerRadius = WidgetTheme.equalizerBarCornerRadius
            bar.layer?.cornerCurve = .continuous
            bar.layer?.backgroundColor = WidgetTheme.primaryForeground.cgColor
            equalizerStack.addArrangedSubview(bar)

            let width = bar.widthAnchor.constraint(equalToConstant: WidgetTheme.equalizerBarWidth)
            let height = bar.heightAnchor.constraint(equalToConstant: WidgetTheme.equalizerBarRestHeight)
            width.isActive = true
            height.isActive = true
            barHeightConstraints.append(height)
        }
    }

    private func configureProcessingIndicator() {
        processingStack.translatesAutoresizingMaskIntoConstraints = false
        processingStack.orientation = .horizontal
        processingStack.alignment = .centerY
        processingStack.distribution = .fillEqually
        processingStack.spacing = WidgetTheme.processingSpacing

        for dot in processingDots {
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.wantsLayer = true
            dot.layer?.cornerRadius = WidgetTheme.processingDotRestSize / 2
            dot.layer?.cornerCurve = .continuous
            dot.layer?.backgroundColor = WidgetTheme.processingDotColor.cgColor
            processingStack.addArrangedSubview(dot)

            let width = dot.widthAnchor.constraint(equalToConstant: WidgetTheme.processingDotRestSize)
            let height = dot.heightAnchor.constraint(equalToConstant: WidgetTheme.processingDotRestSize)
            width.isActive = true
            height.isActive = true
            processingDotSizeConstraints.append(width)
        }
    }

    private func configureConstraints() {
        let glowWidthConstraint = glowView.widthAnchor.constraint(equalToConstant: WidgetTheme.glowRestWidth)
        let glowHeightConstraint = glowView.heightAnchor.constraint(equalToConstant: WidgetTheme.glowRestHeight)
        let idleLineWidthConstraint = idleLineView.widthAnchor.constraint(equalToConstant: WidgetTheme.idleLineRestWidth)
        self.glowWidthConstraint = glowWidthConstraint
        self.glowHeightConstraint = glowHeightConstraint
        self.idleLineWidthConstraint = idleLineWidthConstraint

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: WidgetTheme.widgetOuterSize.width),
            heightAnchor.constraint(equalToConstant: WidgetTheme.widgetOuterSize.height),

            capsuleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            capsuleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            capsuleView.widthAnchor.constraint(equalToConstant: WidgetTheme.widgetCapsuleSize.width),
            capsuleView.heightAnchor.constraint(equalToConstant: WidgetTheme.widgetCapsuleSize.height),

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
            idleLineView.heightAnchor.constraint(equalToConstant: WidgetTheme.idleLineHeight),

            equalizerContainer.centerXAnchor.constraint(equalTo: capsuleView.centerXAnchor),
            equalizerContainer.centerYAnchor.constraint(equalTo: capsuleView.centerYAnchor),
            equalizerContainer.widthAnchor.constraint(equalToConstant: WidgetTheme.equalizerWidth),
            equalizerContainer.heightAnchor.constraint(equalToConstant: WidgetTheme.equalizerHeight),

            equalizerStack.leadingAnchor.constraint(equalTo: equalizerContainer.leadingAnchor),
            equalizerStack.trailingAnchor.constraint(equalTo: equalizerContainer.trailingAnchor),
            equalizerStack.centerYAnchor.constraint(equalTo: equalizerContainer.centerYAnchor),
            equalizerStack.heightAnchor.constraint(equalToConstant: WidgetTheme.equalizerStackHeight),

            processingStack.centerXAnchor.constraint(equalTo: capsuleView.centerXAnchor),
            processingStack.centerYAnchor.constraint(equalTo: capsuleView.centerYAnchor),
            processingStack.widthAnchor.constraint(equalToConstant: WidgetTheme.processingWidth),
            processingStack.heightAnchor.constraint(equalToConstant: WidgetTheme.processingHeight)
        ])
    }

    private func renderVisualState() {
        switch visualState {
        case .idle:
            equalizerContainer.isHidden = true
            processingStack.isHidden = true
            idleLineView.isHidden = false
            applyIdleAppearance()
            animationController.stop()
            animationController.reset(
                barHeightConstraints: barHeightConstraints,
                processingDotSizeConstraints: processingDotSizeConstraints,
                processingDots: processingDots
            )
        case .active:
            equalizerContainer.isHidden = false
            processingStack.isHidden = true
            idleLineView.isHidden = true
            applyActiveAppearance()
            animationController.startEqualizer(
                barHeightConstraints: barHeightConstraints,
                processingDotSizeConstraints: processingDotSizeConstraints,
                processingDots: processingDots
            )
        case .processing:
            equalizerContainer.isHidden = true
            processingStack.isHidden = false
            idleLineView.isHidden = true
            applyProcessingAppearance()
            animationController.startProcessing(
                barHeightConstraints: barHeightConstraints,
                processingDotSizeConstraints: processingDotSizeConstraints,
                processingDots: processingDots
            )
        }
    }

    private func applyIdleAppearance() {
        glowView.layer?.backgroundColor = WidgetTheme.glowColor(hovered: isHovered).cgColor
        borderView.layer?.borderColor = WidgetTheme.borderColor(for: .idle, hovered: isHovered).cgColor
        borderView.layer?.borderWidth = WidgetTheme.borderWidth
        capsuleView.animator().alphaValue = isHovered ? 1.0 : WidgetTheme.idleAlpha
        idleLineWidthConstraint?.animator().constant = isHovered ? WidgetTheme.idleLineHoverWidth : WidgetTheme.idleLineRestWidth
        glowWidthConstraint?.animator().constant = isHovered ? WidgetTheme.glowHoverWidth : WidgetTheme.glowRestWidth
        glowHeightConstraint?.animator().constant = isHovered ? WidgetTheme.glowHoverHeight : WidgetTheme.glowRestHeight
    }

    private func applyActiveAppearance() {
        glowView.layer?.backgroundColor = WidgetTheme.glowColor(hovered: false).cgColor
        borderView.layer?.borderColor = WidgetTheme.borderColor(for: .active, hovered: false).cgColor
        borderView.layer?.borderWidth = WidgetTheme.borderWidth
        capsuleView.animator().alphaValue = 1.0
        glowWidthConstraint?.animator().constant = WidgetTheme.activeGlowWidth
        glowHeightConstraint?.animator().constant = WidgetTheme.activeGlowHeight
    }

    private func applyProcessingAppearance() {
        glowView.layer?.backgroundColor = WidgetTheme.processingGlowColor.cgColor
        borderView.layer?.borderColor = WidgetTheme.borderColor(for: .processing, hovered: false).cgColor
        borderView.layer?.borderWidth = WidgetTheme.borderWidth
        capsuleView.animator().alphaValue = WidgetTheme.processingAlpha
        glowWidthConstraint?.animator().constant = WidgetTheme.processingGlowWidth
        glowHeightConstraint?.animator().constant = WidgetTheme.processingGlowHeight
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
        if abs(deltaX) > WidgetTheme.dragThreshold || abs(deltaY) > WidgetTheme.dragThreshold {
            didDrag = true
        }

        let nextOrigin = NSPoint(x: dragStartWindowOrigin.x + deltaX, y: dragStartWindowOrigin.y + deltaY)
        window.setFrameOrigin(nextOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        guard window != nil else { return }
        guard !didDrag else { return }
        onToggle?()
    }
}

final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
