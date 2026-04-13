import AppKit
import Foundation

final class WidgetContentView: NSView {
    enum VisualState {
        case idle
        case active
        case processing
    }

    var onToggle: (() -> Void)?

    private let idleContainer = NSView()
    private let capsuleView = NSVisualEffectView()
    private let borderView = NSView()
    private let idleGlowView = NSView()
    private let idleTrackView = NSView()
    private let idleIndicatorView = NSView()
    private let contentContainer = NSView()
    private let contentStack = NSStackView()
    private let waveformStack = NSStackView()
    private let waveformBars = (0..<25).map { _ in NSView() }
    private let timerLabel = NSTextField(labelWithString: "00:00")

    private let capsuleBackgroundLayer = CAGradientLayer()
    private let topSheenLayer = CAGradientLayer()
    private let idleTrackGradientLayer = CAGradientLayer()
    private let idleIndicatorGradientLayer = CAGradientLayer()

    private let animationController = WidgetAnimationController()

    private var waveformHeightConstraints: [NSLayoutConstraint] = []
    private var trackingAreaRef: NSTrackingArea?
    private var visualState: VisualState = .idle
    private var isHovered = false

    private var idleGlowWidthConstraint: NSLayoutConstraint?
    private var idleGlowHeightConstraint: NSLayoutConstraint?
    private var idleIndicatorWidthConstraint: NSLayoutConstraint?
    private var currentAudioLevels: [CGFloat] = Array(repeating: 0, count: 25)
    private var recordingStartDate: Date?
    private var frozenDuration: TimeInterval?
    private var timerUpdateTimer: Timer?

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
        capsuleBackgroundLayer.frame = capsuleView.bounds
        topSheenLayer.frame = capsuleView.bounds
        idleTrackGradientLayer.frame = idleTrackView.bounds
        idleIndicatorGradientLayer.frame = idleIndicatorView.bounds
    }

    func apply(state: VisualState) {
        visualState = state
        renderVisualState()
    }

    func updateAudioLevels(_ levels: [CGFloat]) {
        currentAudioLevels = levels
        guard visualState == .active else { return }
        applyLiveWaveform(levels: levels)
    }

    func updateTimer(startDate: Date?, frozenDuration: TimeInterval?) {
        recordingStartDate = startDate
        self.frozenDuration = frozenDuration

        if let frozenDuration {
            timerLabel.stringValue = format(duration: frozenDuration)
        } else if let startDate {
            timerLabel.stringValue = format(duration: Date().timeIntervalSince(startDate))
        } else {
            timerLabel.stringValue = "00:00"
        }

        if visualState == .active, startDate != nil {
            startTimerUpdates()
        } else {
            stopTimerUpdates()
        }
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
        capsuleView.layer?.backgroundColor = WidgetTheme.capsuleFill.cgColor

        capsuleBackgroundLayer.colors = WidgetTheme.backgroundGradientColors
        capsuleBackgroundLayer.startPoint = CGPoint(x: 0.5, y: 0)
        capsuleBackgroundLayer.endPoint = CGPoint(x: 0.5, y: 1)
        capsuleBackgroundLayer.cornerRadius = WidgetTheme.capsuleCornerRadius
        capsuleBackgroundLayer.cornerCurve = .continuous
        capsuleView.layer?.addSublayer(capsuleBackgroundLayer)

        topSheenLayer.colors = WidgetTheme.topSheenGradientColors
        topSheenLayer.startPoint = CGPoint(x: 0.5, y: 0)
        topSheenLayer.endPoint = CGPoint(x: 0.5, y: 1)
        topSheenLayer.cornerRadius = WidgetTheme.capsuleCornerRadius
        topSheenLayer.cornerCurve = .continuous
        capsuleView.layer?.addSublayer(topSheenLayer)
    }

    private func configureSubhierarchy() {
        configureBorder()
        configureIdleGlow()
        configureIdleTrack()
        configureContent()

        idleContainer.translatesAutoresizingMaskIntoConstraints = false
        idleContainer.wantsLayer = true

        addSubview(idleContainer)
        addSubview(capsuleView)
        idleContainer.addSubview(idleGlowView)
        idleContainer.addSubview(idleTrackView)
        idleTrackView.addSubview(idleIndicatorView)
        capsuleView.addSubview(borderView)
        capsuleView.addSubview(contentContainer)
        contentContainer.addSubview(contentStack)
        contentStack.addArrangedSubview(waveformStack)
        contentStack.addArrangedSubview(timerLabel)
    }

    private func configureBorder() {
        borderView.translatesAutoresizingMaskIntoConstraints = false
        borderView.wantsLayer = true
        borderView.layer?.cornerRadius = WidgetTheme.capsuleCornerRadius
        borderView.layer?.cornerCurve = .continuous
        borderView.layer?.borderWidth = WidgetTheme.borderWidth
        borderView.layer?.borderColor = WidgetTheme.borderColor(for: .idle, hovered: false).cgColor
    }

    private func configureIdleGlow() {
        idleGlowView.translatesAutoresizingMaskIntoConstraints = false
        idleGlowView.wantsLayer = true
        idleGlowView.layer?.cornerRadius = WidgetTheme.glowCornerRadius
        idleGlowView.layer?.cornerCurve = .continuous
        idleGlowView.layer?.backgroundColor = WidgetTheme.glowColor(hovered: false).cgColor
    }

    private func configureIdleTrack() {
        idleTrackView.translatesAutoresizingMaskIntoConstraints = false
        idleTrackView.wantsLayer = true
        idleTrackView.layer?.cornerRadius = WidgetTheme.idleTrackCornerRadius
        idleTrackView.layer?.cornerCurve = .continuous
        idleTrackView.layer?.shadowColor = WidgetTheme.idleTrackShadow.cgColor
        idleTrackView.layer?.shadowOpacity = 1
        idleTrackView.layer?.shadowOffset = CGSize(width: 0, height: 2)
        idleTrackView.layer?.shadowRadius = 2
        idleTrackGradientLayer.colors = WidgetTheme.idleTrackGradientColors
        idleTrackGradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        idleTrackGradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        idleTrackGradientLayer.cornerRadius = WidgetTheme.idleTrackCornerRadius
        idleTrackView.layer?.addSublayer(idleTrackGradientLayer)
        idleTrackView.layer?.borderWidth = 0.75
        idleTrackView.layer?.borderColor = WidgetTheme.idleTrackBorder.cgColor

        idleIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        idleIndicatorView.wantsLayer = true
        idleIndicatorView.layer?.cornerRadius = WidgetTheme.idleIndicatorCornerRadius
        idleIndicatorView.layer?.cornerCurve = .continuous
        idleIndicatorGradientLayer.colors = WidgetTheme.idleStandbyGradientColors
        idleIndicatorGradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        idleIndicatorGradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        idleIndicatorGradientLayer.cornerRadius = WidgetTheme.idleIndicatorCornerRadius
        idleIndicatorView.layer?.addSublayer(idleIndicatorGradientLayer)
    }

    private func configureContent() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.distribution = .fill
        contentStack.spacing = WidgetTheme.contentSpacing
        configureWaveform()
        configureTimer()
    }

    private func configureWaveform() {
        waveformStack.translatesAutoresizingMaskIntoConstraints = false
        waveformStack.orientation = .horizontal
        waveformStack.alignment = .centerY
        waveformStack.distribution = .fill
        waveformStack.spacing = WidgetTheme.waveformSpacing

        for bar in waveformBars {
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.wantsLayer = true
            bar.layer?.cornerRadius = WidgetTheme.waveformBarCornerRadius
            bar.layer?.cornerCurve = .continuous
            bar.layer?.backgroundColor = WidgetTheme.activeAccent.cgColor
            waveformStack.addArrangedSubview(bar)

            let width = bar.widthAnchor.constraint(equalToConstant: WidgetTheme.waveformBarWidth)
            let height = bar.heightAnchor.constraint(equalToConstant: 4)
            width.isActive = true
            height.isActive = true
            waveformHeightConstraints.append(height)
        }
    }

    private func configureTimer() {
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        timerLabel.font = WidgetTheme.timerFont
        timerLabel.textColor = WidgetTheme.timerColor
        timerLabel.alignment = .right
        timerLabel.lineBreakMode = .byClipping
        timerLabel.maximumNumberOfLines = 1
        timerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timerLabel.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func configureConstraints() {
        let idleGlowWidthConstraint = idleGlowView.widthAnchor.constraint(equalToConstant: WidgetTheme.idleGlowRestWidth)
        let idleGlowHeightConstraint = idleGlowView.heightAnchor.constraint(equalToConstant: WidgetTheme.idleGlowRestHeight)
        let idleIndicatorWidthConstraint = idleIndicatorView.widthAnchor.constraint(equalToConstant: WidgetTheme.idleIndicatorRestWidth)
        self.idleGlowWidthConstraint = idleGlowWidthConstraint
        self.idleGlowHeightConstraint = idleGlowHeightConstraint
        self.idleIndicatorWidthConstraint = idleIndicatorWidthConstraint

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: WidgetTheme.widgetOuterSize.width),
            heightAnchor.constraint(equalToConstant: WidgetTheme.widgetOuterSize.height),

            idleContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            idleContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            idleContainer.widthAnchor.constraint(equalToConstant: WidgetTheme.widgetOuterSize.width),
            idleContainer.heightAnchor.constraint(equalToConstant: WidgetTheme.widgetOuterSize.height),

            capsuleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            capsuleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            capsuleView.widthAnchor.constraint(equalToConstant: WidgetTheme.widgetCapsuleSize.width),
            capsuleView.heightAnchor.constraint(equalToConstant: WidgetTheme.widgetCapsuleSize.height),

            borderView.leadingAnchor.constraint(equalTo: capsuleView.leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: capsuleView.trailingAnchor),
            borderView.topAnchor.constraint(equalTo: capsuleView.topAnchor),
            borderView.bottomAnchor.constraint(equalTo: capsuleView.bottomAnchor),

            idleGlowView.centerXAnchor.constraint(equalTo: idleContainer.centerXAnchor),
            idleGlowView.centerYAnchor.constraint(equalTo: idleContainer.centerYAnchor),
            idleGlowWidthConstraint,
            idleGlowHeightConstraint,

            idleTrackView.centerXAnchor.constraint(equalTo: idleContainer.centerXAnchor),
            idleTrackView.centerYAnchor.constraint(equalTo: idleContainer.centerYAnchor),
            idleTrackView.widthAnchor.constraint(equalToConstant: WidgetTheme.idleTrackWidth),
            idleTrackView.heightAnchor.constraint(equalToConstant: WidgetTheme.idleTrackHeight),

            idleIndicatorView.centerXAnchor.constraint(equalTo: idleTrackView.centerXAnchor),
            idleIndicatorView.centerYAnchor.constraint(equalTo: idleTrackView.centerYAnchor),
            idleIndicatorWidthConstraint,
            idleIndicatorView.heightAnchor.constraint(equalToConstant: WidgetTheme.idleIndicatorHeight),

            contentContainer.leadingAnchor.constraint(equalTo: capsuleView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: capsuleView.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: capsuleView.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: capsuleView.bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: WidgetTheme.contentHorizontalInset),
            contentStack.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -WidgetTheme.contentHorizontalInset),
            contentStack.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),

            waveformStack.widthAnchor.constraint(equalToConstant: WidgetTheme.waveformWidth),
            waveformStack.heightAnchor.constraint(equalToConstant: WidgetTheme.waveformHeight),
            timerLabel.widthAnchor.constraint(equalToConstant: WidgetTheme.timerWidth)
        ])
    }

    private func renderVisualState() {
        switch visualState {
        case .idle:
            idleContainer.isHidden = false
            capsuleView.isHidden = true
            contentContainer.isHidden = true
            idleGlowView.isHidden = false
            idleTrackView.isHidden = false
            stopTimerUpdates()
            animationController.stop()
            animationController.reset(
                waveformHeightConstraints: waveformHeightConstraints,
                waveformBars: waveformBars,
                auraView: nil
            )
            applyIdleAppearance()
        case .active:
            idleContainer.isHidden = true
            capsuleView.isHidden = false
            contentContainer.isHidden = false
            idleGlowView.isHidden = true
            idleTrackView.isHidden = true
            timerLabel.isHidden = false
            if recordingStartDate != nil {
                startTimerUpdates()
            }
            applyContentAppearance(accent: WidgetTheme.activeAccent, state: .active)
            animationController.stop()
            applyLiveWaveform(levels: currentAudioLevels)
        case .processing:
            idleContainer.isHidden = true
            capsuleView.isHidden = false
            contentContainer.isHidden = false
            idleGlowView.isHidden = true
            idleTrackView.isHidden = true
            timerLabel.isHidden = false
            stopTimerUpdates()
            applyContentAppearance(accent: WidgetTheme.processingAccent, state: .processing)
            animationController.startProcessing(
                waveformHeightConstraints: waveformHeightConstraints,
                waveformBars: waveformBars,
                auraView: nil
            )
        }
    }

    private func applyIdleAppearance() {
        borderView.layer?.borderColor = WidgetTheme.borderColor(for: .idle, hovered: isHovered).cgColor
        idleGlowView.layer?.backgroundColor = WidgetTheme.glowColor(hovered: isHovered).cgColor
        idleIndicatorWidthConstraint?.animator().constant = isHovered ? WidgetTheme.idleIndicatorHoverWidth : WidgetTheme.idleIndicatorRestWidth
        idleGlowWidthConstraint?.animator().constant = isHovered ? WidgetTheme.idleGlowHoverWidth : WidgetTheme.idleGlowRestWidth
        idleGlowHeightConstraint?.animator().constant = isHovered ? WidgetTheme.idleGlowHoverHeight : WidgetTheme.idleGlowRestHeight
        idleContainer.animator().alphaValue = WidgetTheme.idleAlpha
    }

    private func applyContentAppearance(accent: NSColor, state: VisualState) {
        borderView.layer?.borderColor = WidgetTheme.borderColor(for: state, hovered: false).cgColor
        capsuleView.animator().alphaValue = state == .processing ? WidgetTheme.processingAlpha : WidgetTheme.activeAlpha
        waveformBars.forEach { $0.layer?.backgroundColor = accent.cgColor }
    }

    private func applyLiveWaveform(levels: [CGFloat]) {
        guard !waveformHeightConstraints.isEmpty else { return }
        let minimumHeight: CGFloat = 4
        let maximumAdditionalHeight: CGFloat = 20

        for (index, constraint) in waveformHeightConstraints.enumerated() {
            let level = levels.indices.contains(index) ? levels[index] : 0
            let shaped = max(0, min(1, level))
            constraint.animator().constant = minimumHeight + (maximumAdditionalHeight * shaped)
            waveformBars[index].animator().alphaValue = 0.58 + (0.42 * shaped)
        }
    }

    private func startTimerUpdates() {
        guard timerUpdateTimer == nil else { return }
        timerUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tickTimer()
        }
        tickTimer()
    }

    private func stopTimerUpdates() {
        timerUpdateTimer?.invalidate()
        timerUpdateTimer = nil
    }

    private func tickTimer() {
        guard visualState == .active, let recordingStartDate else { return }
        timerLabel.stringValue = format(duration: Date().timeIntervalSince(recordingStartDate))
    }

    private func format(duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
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
