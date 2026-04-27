import AppKit

enum ActivityOverlayMode: Equatable {
    case hidden
    case recordingWave
    case meetingBlip

    static func mode(for state: StatusBarController.State) -> ActivityOverlayMode {
        switch state {
        case .recording:
            return .recordingWave
        case .meetingRecording:
            return .meetingBlip
        case .idle, .transcribing, .meetingStarting, .meetingStopping, .downloading, .waitingForPermission, .copiedToClipboard, .error:
            return .hidden
        }
    }
}

final class ActivityOverlayController {
    private let panel: NSPanel
    private let overlayView: ActivityOverlayView
    private var currentMode: ActivityOverlayMode = .hidden

    init() {
        overlayView = ActivityOverlayView(frame: .zero)
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.contentView = overlayView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        hideAll()
    }

    func update(for state: StatusBarController.State) {
        if Thread.isMainThread {
            apply(mode: ActivityOverlayMode.mode(for: state))
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.apply(mode: ActivityOverlayMode.mode(for: state))
            }
        }
    }

    func hideAll() {
        if Thread.isMainThread {
            panel.orderOut(nil)
            overlayView.stopAnimating()
            currentMode = .hidden
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.hideAll()
            }
        }
    }

    @objc private func handleScreenParametersDidChange() {
        guard currentMode != .hidden else { return }
        positionPanel(for: currentMode)
    }

    private func apply(mode: ActivityOverlayMode) {
        guard mode != currentMode || mode == .hidden else {
            if mode != .hidden {
                positionPanel(for: mode)
            }
            return
        }

        currentMode = mode

        switch mode {
        case .hidden:
            panel.orderOut(nil)
            overlayView.stopAnimating()
        case .recordingWave, .meetingBlip:
            overlayView.mode = mode
            overlayView.startAnimating()
            positionPanel(for: mode)
            panel.orderFrontRegardless()
        }
    }

    private func positionPanel(for mode: ActivityOverlayMode) {
        let size = size(for: mode)
        let screen = targetScreen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let origin: NSPoint
        switch mode {
        case .recordingWave:
            origin = NSPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.minY + 56
            )
        case .meetingBlip:
            origin = NSPoint(
                x: visibleFrame.maxX - size.width - 20,
                y: visibleFrame.maxY - size.height - 20
            )
        case .hidden:
            return
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        overlayView.frame = NSRect(origin: .zero, size: size)
        overlayView.needsDisplay = true
    }

    private func size(for mode: ActivityOverlayMode) -> NSSize {
        switch mode {
        case .recordingWave:
            return NSSize(width: 220, height: 64)
        case .meetingBlip:
            return NSSize(width: 54, height: 24)
        case .hidden:
            return .zero
        }
    }

    private func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
    }
}

private final class ActivityOverlayView: NSView {
    var mode: ActivityOverlayMode = .hidden {
        didSet { needsDisplay = true }
    }

    private var animationTimer: Timer?
    private var frameIndex = 0
    private let frameCount = 30

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    func startAnimating() {
        stopAnimating()
        frameIndex = 0
        needsDisplay = true
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.frameIndex = (self.frameIndex + 1) % self.frameCount
            self.needsDisplay = true
        }
        if let animationTimer {
            RunLoop.main.add(animationTimer, forMode: .common)
        }
    }

    func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        frameIndex = 0
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        switch mode {
        case .hidden:
            break
        case .recordingWave:
            drawRecordingWave(in: dirtyRect)
        case .meetingBlip:
            drawMeetingBlip(in: dirtyRect)
        }
    }

    private func drawRecordingWave(in rect: NSRect) {
        let backgroundRect = rect.insetBy(dx: 8, dy: 8)
        NSColor.white.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: backgroundRect, xRadius: backgroundRect.height / 2, yRadius: backgroundRect.height / 2).fill()

        let t = Double(frameIndex) / Double(frameCount)
        let barWidth: CGFloat = 14
        let gap: CGFloat = 10
        let baseHeights: [CGFloat] = [14, 24, 34, 24, 14]
        let minScale: CGFloat = 0.35
        let phaseOffsets: [Double] = [0.0, 0.12, 0.24, 0.36, 0.48]
        let totalWidth = CGFloat(baseHeights.count) * barWidth + CGFloat(baseHeights.count - 1) * gap
        let startX = rect.midX - totalWidth / 2

        for (index, baseHeight) in baseHeights.enumerated() {
            let phase = t - phaseOffsets[index]
            let scale = minScale + (1.0 - minScale) * CGFloat((sin(phase * 2.0 * .pi) + 1.0) / 2.0)
            let height = baseHeight * scale
            let x = startX + CGFloat(index) * (barWidth + gap)
            let y = rect.midY - height / 2
            let barRect = NSRect(x: x, y: y, width: barWidth, height: height)
            NSColor.white.withAlphaComponent(0.2 + CGFloat(index) * 0.03).setFill()
            NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
    }

    private func drawMeetingBlip(in rect: NSRect) {
        let t = Double(frameIndex) / Double(frameCount)
        let dotSize: CGFloat = 6
        let gap: CGFloat = 5
        let totalWidth = 3 * dotSize + 2 * gap
        let startX = rect.midX - totalWidth / 2
        let centerY = rect.midY - dotSize / 2

        NSColor.white.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), xRadius: 8, yRadius: 8).fill()

        for index in 0..<3 {
            let phase = t - Double(index) * 0.18
            let alpha = 0.14 + 0.18 * max(0, CGFloat((sin(phase * 2.0 * .pi) + 1.0) / 2.0))
            let bounce = 2.0 * max(0, CGFloat(sin(phase * 2.0 * .pi)))
            let dotRect = NSRect(
                x: startX + CGFloat(index) * (dotSize + gap),
                y: centerY + bounce,
                width: dotSize,
                height: dotSize
            )
            NSColor.white.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }
    }
}
