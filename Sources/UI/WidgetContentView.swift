import AppKit
import Foundation

final class WidgetContentView: NSView {
    enum VisualState {
        case idle
        case dictationActive
        case recordingActive
        case meetingDetected
        case processingDictation
        case processingRecording
    }

    var onToggle: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onDismissMeeting: (() -> Void)?
    var onAcceptMeeting: (() -> Void)?

    private let idleContainer = NSView()
    private let capsuleView = NSVisualEffectView()
    private let borderView = NSView()
    private let idleGlowView = NSView()
    private let idleTrackView = NSView()
    private let idleIndicatorView = NSView()
    private let contentContainer = NSView()

    private let dictationRow = NSStackView()
    private let recordingRow = NSStackView()
    private let meetingRow = NSStackView()
    private let processingRow = NSStackView()

    private let recordingStopSlot = NSView()
    private let stopButton = NSButton()
    private let meetingTextStack = NSStackView()
    private let meetingEyebrowLabel = NSTextField(labelWithString: "Meeting detected")
    private let meetingTitleLabel = NSTextField(labelWithString: "Record session?")
    private let meetingActionsStack = NSStackView()
    private let dismissMeetingButton = NSButton()
    private let acceptMeetingButton = NSButton()
    private let acceptMeetingDotView = NSView()

    private let dictationWaveformView = WaveformStripView()
    private let recordingWaveformView = WaveformStripView()
    private let processingWaveformView = WaveformStripView()

    private let dictationTimerLabel = NSTextField(labelWithString: "00:00")
    private let recordingTimerLabel = NSTextField(labelWithString: "00:00")
    private let processingTimerLabel = NSTextField(labelWithString: "00:00")

    private let capsuleBackgroundLayer = CAGradientLayer()
    private let topSheenLayer = CAGradientLayer()
    private let idleTrackGradientLayer = CAGradientLayer()
    private let idleIndicatorGradientLayer = CAGradientLayer()

    private let animationController = WidgetAnimationController()

    private var trackingAreaRef: NSTrackingArea?
    private var visualState: VisualState = .idle
    private var isHovered = false

    private var idleGlowWidthConstraint: NSLayoutConstraint?
    private var idleGlowHeightConstraint: NSLayoutConstraint?
    private var idleIndicatorWidthConstraint: NSLayoutConstraint?
    private var outerWidthConstraint: NSLayoutConstraint?
    private var outerHeightConstraint: NSLayoutConstraint?
    private var idleContainerWidthConstraint: NSLayoutConstraint?
    private var idleContainerHeightConstraint: NSLayoutConstraint?
    private var capsuleWidthConstraint: NSLayoutConstraint?
    private var capsuleHeightConstraint: NSLayoutConstraint?
    private var currentAudioLevels: [CGFloat] = []
    private var recordingStartDate: Date?
    private var frozenDuration: TimeInterval?
    private var timerUpdateTimer: Timer?
    private var meetingPromptAppName = "Meeting"

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
        switch visualState {
        case .dictationActive:
            dictationWaveformView.apply(levels: levels, animated: true)
        case .recordingActive:
            recordingWaveformView.apply(levels: levels, animated: true)
        default:
            break
        }
    }

    func updateTimer(startDate: Date?, frozenDuration: TimeInterval?) {
        recordingStartDate = startDate
        self.frozenDuration = frozenDuration

        let resolvedValue: String
        if let frozenDuration {
            resolvedValue = format(duration: frozenDuration)
        } else if let startDate {
            resolvedValue = format(duration: Date().timeIntervalSince(startDate))
        } else {
            resolvedValue = "00:00"
        }

        setTimerText(resolvedValue)

        if (visualState == .dictationActive || visualState == .recordingActive), startDate != nil {
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
        configureRows()

        idleContainer.translatesAutoresizingMaskIntoConstraints = false
        idleContainer.wantsLayer = true

        addSubview(idleContainer)
        addSubview(capsuleView)
        idleContainer.addSubview(idleGlowView)
        idleContainer.addSubview(idleTrackView)
        idleTrackView.addSubview(idleIndicatorView)
        capsuleView.addSubview(borderView)
        capsuleView.addSubview(contentContainer)
        contentContainer.addSubview(dictationRow)
        contentContainer.addSubview(recordingRow)
        contentContainer.addSubview(meetingRow)
        contentContainer.addSubview(processingRow)
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

    private func configureRows() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        configureRowStack(dictationRow)
        configureRowStack(recordingRow)
        configureRowStack(meetingRow)
        configureRowStack(processingRow)

        configureStopButton()
        configureMeetingPrompt()
        configureTimerLabel(dictationTimerLabel)
        configureTimerLabel(recordingTimerLabel)
        configureTimerLabel(processingTimerLabel)

        dictationWaveformView.translatesAutoresizingMaskIntoConstraints = false
        dictationWaveformView.configure(for: .dictation, accentColor: WidgetTheme.activeAccent)

        recordingWaveformView.translatesAutoresizingMaskIntoConstraints = false
        recordingWaveformView.configure(for: .recording, accentColor: WidgetTheme.activeAccent)

        processingWaveformView.translatesAutoresizingMaskIntoConstraints = false
        processingWaveformView.configure(for: .processing, accentColor: WidgetTheme.processingAccent)

        recordingStopSlot.translatesAutoresizingMaskIntoConstraints = false
        recordingStopSlot.addSubview(stopButton)

        dictationRow.addArrangedSubview(dictationWaveformView)
        dictationRow.addArrangedSubview(dictationTimerLabel)

        recordingRow.addArrangedSubview(recordingStopSlot)
        recordingRow.addArrangedSubview(recordingWaveformView)
        recordingRow.addArrangedSubview(recordingTimerLabel)

        meetingTextStack.translatesAutoresizingMaskIntoConstraints = false
        meetingTextStack.orientation = .vertical
        meetingTextStack.alignment = .leading
        meetingTextStack.spacing = 2
        meetingRow.addArrangedSubview(meetingTextStack)
        meetingRow.addArrangedSubview(NSView())
        meetingRow.addArrangedSubview(meetingActionsStack)

        meetingTextStack.addArrangedSubview(meetingEyebrowLabel)
        meetingTextStack.addArrangedSubview(meetingTitleLabel)
        meetingActionsStack.addArrangedSubview(dismissMeetingButton)
        meetingActionsStack.addArrangedSubview(acceptMeetingButton)

        processingRow.addArrangedSubview(processingWaveformView)
        processingRow.addArrangedSubview(processingTimerLabel)
    }

    private func configureRowStack(_ row: NSStackView) {
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = WidgetTheme.contentSpacing
    }

    private func configureStopButton() {
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.isBordered = false
        stopButton.bezelStyle = .regularSquare
        stopButton.wantsLayer = true
        stopButton.layer?.cornerRadius = WidgetTheme.stopButtonCornerRadius
        stopButton.layer?.cornerCurve = .continuous
        stopButton.layer?.backgroundColor = WidgetTheme.stopButtonFill.cgColor
        stopButton.layer?.borderWidth = 1
        stopButton.layer?.borderColor = WidgetTheme.stopButtonBorder.cgColor
        stopButton.contentTintColor = WidgetTheme.stopButtonSymbol
        stopButton.image = NSImage(
            systemSymbolName: "stop.fill",
            accessibilityDescription: "Stop recording"
        )?.withSymbolConfiguration(.init(pointSize: 8, weight: .bold))
        stopButton.imagePosition = .imageOnly
        stopButton.imageScaling = .scaleProportionallyDown
        stopButton.target = self
        stopButton.action = #selector(handleStopButton)
    }

    private func configureMeetingPrompt() {
        meetingEyebrowLabel.translatesAutoresizingMaskIntoConstraints = false
        meetingEyebrowLabel.font = WidgetTheme.meetingEyebrowFont
        meetingEyebrowLabel.textColor = WidgetTheme.meetingEyebrowColor

        meetingTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        meetingTitleLabel.font = WidgetTheme.meetingTitleFont
        meetingTitleLabel.textColor = WidgetTheme.meetingTitleColor

        meetingActionsStack.translatesAutoresizingMaskIntoConstraints = false
        meetingActionsStack.orientation = .horizontal
        meetingActionsStack.alignment = .centerY
        meetingActionsStack.spacing = 8

        dismissMeetingButton.translatesAutoresizingMaskIntoConstraints = false
        dismissMeetingButton.isBordered = false
        dismissMeetingButton.bezelStyle = .regularSquare
        dismissMeetingButton.wantsLayer = true
        dismissMeetingButton.layer?.cornerRadius = WidgetTheme.meetingButtonCornerRadius
        dismissMeetingButton.layer?.cornerCurve = .continuous
        dismissMeetingButton.layer?.backgroundColor = WidgetTheme.meetingButtonFill.cgColor
        dismissMeetingButton.layer?.borderWidth = 1
        dismissMeetingButton.layer?.borderColor = WidgetTheme.meetingButtonBorder.cgColor
        dismissMeetingButton.contentTintColor = WidgetTheme.meetingDismissSymbol
        dismissMeetingButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "Dismiss meeting recording prompt"
        )?.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        dismissMeetingButton.imagePosition = .imageOnly
        dismissMeetingButton.imageScaling = .scaleProportionallyDown
        dismissMeetingButton.target = self
        dismissMeetingButton.action = #selector(handleDismissMeetingButton)

        acceptMeetingButton.translatesAutoresizingMaskIntoConstraints = false
        acceptMeetingButton.isBordered = false
        acceptMeetingButton.bezelStyle = .regularSquare
        acceptMeetingButton.wantsLayer = true
        acceptMeetingButton.layer?.cornerRadius = WidgetTheme.meetingButtonCornerRadius
        acceptMeetingButton.layer?.cornerCurve = .continuous
        acceptMeetingButton.layer?.backgroundColor = WidgetTheme.meetingButtonFill.cgColor
        acceptMeetingButton.layer?.borderWidth = 1.5
        acceptMeetingButton.layer?.borderColor = WidgetTheme.meetingButtonBorder.cgColor
        acceptMeetingButton.target = self
        acceptMeetingButton.action = #selector(handleAcceptMeetingButton)

        acceptMeetingDotView.translatesAutoresizingMaskIntoConstraints = false
        acceptMeetingDotView.wantsLayer = true
        acceptMeetingDotView.layer?.cornerRadius = 4.5
        acceptMeetingDotView.layer?.cornerCurve = .continuous
        acceptMeetingDotView.layer?.backgroundColor = WidgetTheme.meetingRecordDot.cgColor
        acceptMeetingButton.addSubview(acceptMeetingDotView)
    }

    private func configureTimerLabel(_ label: NSTextField) {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = WidgetTheme.timerFont
        label.textColor = WidgetTheme.timerColor
        label.alignment = .right
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func configureConstraints() {
        let idleGlowWidthConstraint = idleGlowView.widthAnchor.constraint(equalToConstant: WidgetTheme.idleGlowRestWidth)
        let idleGlowHeightConstraint = idleGlowView.heightAnchor.constraint(equalToConstant: WidgetTheme.idleGlowRestHeight)
        let idleIndicatorWidthConstraint = idleIndicatorView.widthAnchor.constraint(equalToConstant: WidgetTheme.idleIndicatorRestWidth)
        self.idleGlowWidthConstraint = idleGlowWidthConstraint
        self.idleGlowHeightConstraint = idleGlowHeightConstraint
        self.idleIndicatorWidthConstraint = idleIndicatorWidthConstraint
        let outerWidthConstraint = widthAnchor.constraint(equalToConstant: WidgetTheme.widgetOuterSize(for: .idle).width)
        let outerHeightConstraint = heightAnchor.constraint(equalToConstant: WidgetTheme.widgetOuterSize(for: .idle).height)
        let idleContainerWidthConstraint = idleContainer.widthAnchor.constraint(equalToConstant: WidgetTheme.widgetOuterSize(for: .idle).width)
        let idleContainerHeightConstraint = idleContainer.heightAnchor.constraint(equalToConstant: WidgetTheme.widgetOuterSize(for: .idle).height)
        let capsuleWidthConstraint = capsuleView.widthAnchor.constraint(equalToConstant: WidgetTheme.widgetCapsuleSize(for: .idle).width)
        let capsuleHeightConstraint = capsuleView.heightAnchor.constraint(equalToConstant: WidgetTheme.widgetCapsuleSize(for: .idle).height)
        self.outerWidthConstraint = outerWidthConstraint
        self.outerHeightConstraint = outerHeightConstraint
        self.idleContainerWidthConstraint = idleContainerWidthConstraint
        self.idleContainerHeightConstraint = idleContainerHeightConstraint
        self.capsuleWidthConstraint = capsuleWidthConstraint
        self.capsuleHeightConstraint = capsuleHeightConstraint

        let dictationGeometry = WidgetTheme.waveformGeometry(for: .dictation)
        let recordingGeometry = WidgetTheme.waveformGeometry(for: .recording)
        let processingGeometry = WidgetTheme.waveformGeometry(for: .processing)

        NSLayoutConstraint.activate([
            outerWidthConstraint,
            outerHeightConstraint,

            idleContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            idleContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            idleContainerWidthConstraint,
            idleContainerHeightConstraint,

            capsuleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            capsuleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            capsuleWidthConstraint,
            capsuleHeightConstraint,

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

            dictationRow.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: WidgetTheme.contentHorizontalInset),
            dictationRow.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -WidgetTheme.contentHorizontalInset),
            dictationRow.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),

            recordingRow.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: WidgetTheme.contentHorizontalInset),
            recordingRow.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -WidgetTheme.contentHorizontalInset),
            recordingRow.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),

            meetingRow.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: WidgetTheme.meetingContentHorizontalInset),
            meetingRow.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -WidgetTheme.meetingContentHorizontalInset),
            meetingRow.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),

            processingRow.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: WidgetTheme.contentHorizontalInset),
            processingRow.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -WidgetTheme.contentHorizontalInset),
            processingRow.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),

            recordingStopSlot.widthAnchor.constraint(equalToConstant: WidgetTheme.stopButtonSlotWidth),
            stopButton.centerXAnchor.constraint(equalTo: recordingStopSlot.centerXAnchor),
            stopButton.centerYAnchor.constraint(equalTo: recordingStopSlot.centerYAnchor),
            stopButton.widthAnchor.constraint(equalToConstant: WidgetTheme.stopButtonSize),
            stopButton.heightAnchor.constraint(equalToConstant: WidgetTheme.stopButtonSize),

            dictationWaveformView.widthAnchor.constraint(equalToConstant: dictationGeometry.width),
            dictationWaveformView.heightAnchor.constraint(equalToConstant: dictationGeometry.height),
            dictationTimerLabel.widthAnchor.constraint(equalToConstant: WidgetTheme.timerSlotWidth),

            recordingWaveformView.widthAnchor.constraint(equalToConstant: recordingGeometry.width),
            recordingWaveformView.heightAnchor.constraint(equalToConstant: recordingGeometry.height),
            recordingTimerLabel.widthAnchor.constraint(equalToConstant: WidgetTheme.timerSlotWidth),

            dismissMeetingButton.widthAnchor.constraint(equalToConstant: WidgetTheme.meetingButtonSize),
            dismissMeetingButton.heightAnchor.constraint(equalToConstant: WidgetTheme.meetingButtonSize),
            acceptMeetingButton.widthAnchor.constraint(equalToConstant: WidgetTheme.meetingButtonSize),
            acceptMeetingButton.heightAnchor.constraint(equalToConstant: WidgetTheme.meetingButtonSize),
            acceptMeetingDotView.centerXAnchor.constraint(equalTo: acceptMeetingButton.centerXAnchor),
            acceptMeetingDotView.centerYAnchor.constraint(equalTo: acceptMeetingButton.centerYAnchor),
            acceptMeetingDotView.widthAnchor.constraint(equalToConstant: 9),
            acceptMeetingDotView.heightAnchor.constraint(equalToConstant: 9),

            processingWaveformView.widthAnchor.constraint(equalToConstant: processingGeometry.width),
            processingWaveformView.heightAnchor.constraint(equalToConstant: processingGeometry.height),
            processingTimerLabel.widthAnchor.constraint(equalToConstant: WidgetTheme.timerSlotWidth)
        ])
    }

    private func renderVisualState() {
        dictationRow.isHidden = true
        recordingRow.isHidden = true
        meetingRow.isHidden = true
        processingRow.isHidden = true
        stopMeetingPulseAnimation()
        updateSize(for: visualState)

        switch visualState {
        case .idle:
            idleContainer.isHidden = false
            capsuleView.isHidden = true
            stopTimerUpdates()
            animationController.stop()
            applyIdleAppearance()
        case .dictationActive:
            idleContainer.isHidden = true
            capsuleView.isHidden = false
            dictationRow.isHidden = false
            if recordingStartDate != nil {
                startTimerUpdates()
            }
            animationController.stop()
            applyContentAppearance(accent: WidgetTheme.activeAccent, state: .dictationActive)
            dictationWaveformView.apply(levels: currentAudioLevels, animated: false)
        case .recordingActive:
            idleContainer.isHidden = true
            capsuleView.isHidden = false
            recordingRow.isHidden = false
            if recordingStartDate != nil {
                startTimerUpdates()
            }
            animationController.stop()
            applyContentAppearance(accent: WidgetTheme.activeAccent, state: .recordingActive)
            recordingWaveformView.apply(levels: currentAudioLevels, animated: false)
        case .meetingDetected:
            idleContainer.isHidden = true
            capsuleView.isHidden = false
            meetingRow.isHidden = false
            stopTimerUpdates()
            animationController.stop()
            applyContentAppearance(accent: WidgetTheme.activeAccent, state: .meetingDetected)
            startMeetingPulseAnimation()
        case .processingDictation, .processingRecording:
            idleContainer.isHidden = true
            capsuleView.isHidden = false
            processingRow.isHidden = false
            stopTimerUpdates()
            applyContentAppearance(accent: WidgetTheme.processingAccent, state: visualState)
            let processingBarCount = WidgetTheme.waveformGeometry(for: .processing).barCount
            animationController.startProcessing(barCount: processingBarCount) { [weak self] levels in
                self?.processingWaveformView.apply(levels: levels, animated: true)
            }
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
        let isProcessing = state == .processingDictation || state == .processingRecording
        capsuleView.animator().alphaValue = isProcessing ? WidgetTheme.processingAlpha : WidgetTheme.activeAlpha
        capsuleView.layer?.cornerRadius = WidgetTheme.capsuleCornerRadius(for: state)
        borderView.layer?.cornerRadius = WidgetTheme.capsuleCornerRadius(for: state)
        capsuleBackgroundLayer.cornerRadius = WidgetTheme.capsuleCornerRadius(for: state)
        topSheenLayer.cornerRadius = WidgetTheme.capsuleCornerRadius(for: state)
        dictationWaveformView.setAccentColor(accent)
        recordingWaveformView.setAccentColor(accent)
        processingWaveformView.setAccentColor(accent)
    }

    private func updateSize(for state: VisualState) {
        let outerSize = WidgetTheme.widgetOuterSize(for: state)
        let capsuleSize = WidgetTheme.widgetCapsuleSize(for: state)
        outerWidthConstraint?.constant = outerSize.width
        outerHeightConstraint?.constant = outerSize.height
        idleContainerWidthConstraint?.constant = outerSize.width
        idleContainerHeightConstraint?.constant = outerSize.height
        capsuleWidthConstraint?.constant = capsuleSize.width
        capsuleHeightConstraint?.constant = capsuleSize.height
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
        guard (visualState == .dictationActive || visualState == .recordingActive), let recordingStartDate else { return }
        setTimerText(format(duration: Date().timeIntervalSince(recordingStartDate)))
    }

    private func setTimerText(_ text: String) {
        dictationTimerLabel.stringValue = text
        recordingTimerLabel.stringValue = text
        processingTimerLabel.stringValue = text
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
        guard visualState != .meetingDetected else { return }
        onToggle?()
    }

    @objc
    private func handleStopButton() {
        onStopRecording?()
    }

    func updateMeetingPrompt(appName: String) {
        meetingPromptAppName = appName
        dismissMeetingButton.toolTip = "Dismiss \(appName) meeting suggestion"
        acceptMeetingButton.toolTip = "Record \(appName) session"
    }

    @objc
    private func handleDismissMeetingButton() {
        onDismissMeeting?()
    }

    @objc
    private func handleAcceptMeetingButton() {
        onAcceptMeeting?()
    }

    private func startMeetingPulseAnimation() {
        guard let layer = acceptMeetingDotView.layer else { return }
        if layer.animation(forKey: "meetingPulseOpacity") != nil {
            return
        }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.4
        animation.toValue = 1.0
        animation.duration = 0.75
        animation.autoreverses = true
        animation.repeatCount = .infinity
        layer.add(animation, forKey: "meetingPulseOpacity")
    }

    private func stopMeetingPulseAnimation() {
        acceptMeetingDotView.layer?.removeAnimation(forKey: "meetingPulseOpacity")
    }
}

final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
