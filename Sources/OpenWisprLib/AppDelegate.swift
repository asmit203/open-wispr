import AppKit

public class AppDelegate: NSObject, NSApplicationDelegate {
    enum CaptureMode {
        case none
        case dictation
        case assistant
    }

    var statusBar: StatusBarController!
    var activityOverlay: ActivityOverlayController!
    var hotkeyManager: HotkeyManager?
    var assistantHotkeyManager: HotkeyManager?
    var recorder: AudioRecorder!
    var transcriber: Transcriber!
    var inserter: TextInserter!
    var config: Config!
    var isPressed = false
    var isReady = false
    var isMeetingCaptureActive = false
    var isStoppingMeetingCapture = false
    var meetingCaptureSession: SystemAudioCaptureSession?
    var meetingTranscriptSession: TranscriptLogStore.TranscriptLogSession?
    let meetingChunkQueue = DispatchQueue(label: "open-wispr.meeting-transcription")
    let meetingChunkGroup = DispatchGroup()
    private var startupPreparationComplete = false
    private var hasLoggedAccessibilityGranted = false
    private var hasRequestedAccessibility = false
    private var meetingTranscriptContext = ""
    private var captureMode: CaptureMode = .none
    private let assistantSkillStore = AssistantSkillStore()
    private let assistantHistoryStore = AssistantHistoryStore()
    private let assistantMatcher = AssistantMatcher()
    private let assistantExecutor = AssistantExecutor()
    private var pendingAssistantRequest: SkillExecutionRequest?
    public var lastTranscription: String?
    public var currentMeetingTranscriptURL: URL? {
        meetingTranscriptSession?.fileURL
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        statusBar = StatusBarController()
        activityOverlay = ActivityOverlayController()
        statusBar.onStateChange = { [weak self] state in
            self?.activityOverlay.update(for: state)
        }
        activityOverlay.update(for: statusBar.state)
        recorder = AudioRecorder()
        let dashboard = AssistantDashboardWindowController.shared
        dashboard.executeTranscriptHandler = { [weak self] input in
            self?.handleAssistantTranscript(input, source: .dashboard, originalTranscript: input, allowDictationFallback: false)
        }
        dashboard.executePendingHandler = { [weak self] in
            self?.executePendingAssistantRequest()
        }
        dashboard.onConfigChange = { [weak self] newConfig in
            self?.applyConfigChange(newConfig)
        }
        dashboard.onSkillsChanged = { [weak self] in
            self?.statusBar.buildMenu()
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setup()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        activityOverlay?.hideAll()
    }

    private func setup() {
        do {
            try setupInner()
        } catch {
            print("Fatal setup error: \(error.localizedDescription)")
        }
    }

    private func setupInner() throws {
        config = Config.load()
        inserter = TextInserter()
        recorder.preferredDeviceID = config.audioInputDeviceID
        if Config.effectiveMaxRecordings(config.maxRecordings) == 0 {
            RecordingStore.deleteAllRecordings()
        }
        transcriber = Transcriber(modelSize: config.modelSize, language: config.language)
        transcriber.spokenPunctuation = config.spokenPunctuation?.value ?? false
        transcriber.customDictionary = config.customDictionary ?? []
        Permissions.noteLaunchPermissionState()

        DispatchQueue.main.async {
            self.statusBar.reprocessHandler = { [weak self] url in
                self?.reprocess(audioURL: url)
            }
            self.statusBar.onConfigChange = { [weak self] newConfig in
                self?.applyConfigChange(newConfig)
            }
            self.statusBar.startMeetingCaptureHandler = { [weak self] in
                self?.startMeetingCapture()
            }
            self.statusBar.stopMeetingCaptureHandler = { [weak self] in
                self?.stopMeetingCapture()
            }
            self.statusBar.openTranscriptFolderHandler = { [weak self] in
                self?.openMeetingTranscriptFolder()
            }
            self.statusBar.openCurrentTranscriptHandler = { [weak self] in
                self?.openCurrentMeetingTranscript()
            }
            self.statusBar.openAssistantDashboardHandler = { [weak self] in
                self?.openAssistantDashboard()
            }
            self.statusBar.buildMenu()
        }

        if Transcriber.findWhisperBinary() == nil {
            print("Error: whisper-cpp not found. Install it with: brew install whisper-cpp")
            return
        }

        requestAccessibilityIfNeeded()

        if !Transcriber.modelExists(modelSize: config.modelSize) {
            DispatchQueue.main.async {
                self.statusBar.state = .downloading
                self.statusBar.updateDownloadProgress("Downloading \(self.config.modelSize) model...")
            }
            print("Downloading \(config.modelSize) model...")
            try ModelDownloader.download(modelSize: config.modelSize) { [weak self] percent in
                DispatchQueue.main.async {
                    let pct = Int(percent)
                    self?.statusBar.updateDownloadProgress("Downloading \(self?.config.modelSize ?? "") model... \(pct)%", percent: percent)
                }
            }
            DispatchQueue.main.async {
                self.statusBar.updateDownloadProgress(nil)
            }
        }

        if let modelPath = Transcriber.findModel(modelSize: config.modelSize) {
            let modelURL = URL(fileURLWithPath: modelPath)
            if !ModelDownloader.isValidGGMLFile(at: modelURL) {
                let msg = "Model file is corrupted. Re-download with: open-wispr download-model \(config.modelSize)"
                print("Error: \(msg)")
                DispatchQueue.main.async {
                    self.statusBar.state = .error(msg)
                    self.statusBar.buildMenu()
                }
                return
            }
        }

        startupPreparationComplete = true
        DispatchQueue.main.async { [weak self] in
            self?.startListeningIfPossible()
        }
    }

    @objc private func handleApplicationDidBecomeActive() {
        if Permissions.screenCapturePermissionWasGrantedAfterLaunch() {
            presentError("Restart OpenWispr after granting Screen & System Audio Recording permission")
        }

        requestAccessibilityIfNeeded(promptUser: false)

        DispatchQueue.main.async { [weak self] in
            self?.startListeningIfPossible()
        }
    }

    private func requestAccessibilityIfNeeded(promptUser: Bool = true) {
        guard !Permissions.hasAccessibilityPermission() else {
            hasRequestedAccessibility = false
            logAccessibilityGrantedIfNeeded()
            return
        }

        if !hasRequestedAccessibility {
            print("Accessibility: not granted")
        }
        if promptUser && !hasRequestedAccessibility {
            _ = Permissions.promptAccessibility()
            Permissions.openAccessibilitySettings()
            hasRequestedAccessibility = true
        }

        DispatchQueue.main.async {
            self.statusBar.state = .waitingForPermission
            self.statusBar.buildMenu()
        }
    }

    private func logAccessibilityGrantedIfNeeded() {
        guard !hasLoggedAccessibilityGranted else { return }
        print("Accessibility: granted")
        hasLoggedAccessibilityGranted = true
    }

    private func startListeningIfPossible() {
        guard startupPreparationComplete, !isReady else { return }
        guard Permissions.hasAccessibilityPermission() else {
            statusBar.state = .waitingForPermission
            statusBar.buildMenu()
            return
        }

        logAccessibilityGrantedIfNeeded()
        startListening()
    }

    private func startListening() {
        hotkeyManager = HotkeyManager(
            keyCode: config.hotkey.keyCode,
            modifiers: config.hotkey.modifierFlags
        )

        hotkeyManager?.start(
            onKeyDown: { [weak self] in
                self?.handleKeyDown()
            },
            onKeyUp: { [weak self] in
                self?.handleKeyUp()
            }
        )

        isReady = true
        configureAssistantHotkeyManager()
        statusBar.state = .idle
        statusBar.buildMenu()

        let hotkeyDesc = KeyCodes.describe(keyCode: config.hotkey.keyCode, modifiers: config.hotkey.modifiers)
        print("open-wispr v\(OpenWispr.version)")
        print("Hotkey: \(hotkeyDesc)")
        print("Model: \(config.modelSize)")
        print("Ready.")
    }

    public func reloadConfig() {
        let newConfig = Config.load()
        applyConfigChange(newConfig)
    }

    func applyConfigChange(_ newConfig: Config) {
        guard isReady else { return }
        let wasDownloading: Bool
        if case .downloading = statusBar.state { wasDownloading = true } else { wasDownloading = false }
        config = newConfig
        recorder.preferredDeviceID = config.audioInputDeviceID
        transcriber = Transcriber(modelSize: config.modelSize, language: config.language)
        transcriber.spokenPunctuation = config.spokenPunctuation?.value ?? false
        transcriber.customDictionary = config.customDictionary ?? []
        inserter = TextInserter()

        hotkeyManager?.stop()
        assistantHotkeyManager?.stop()
        hotkeyManager = HotkeyManager(
            keyCode: config.hotkey.keyCode,
            modifiers: config.hotkey.modifierFlags
        )
        hotkeyManager?.start(
            onKeyDown: { [weak self] in self?.handleKeyDown() },
            onKeyUp: { [weak self] in self?.handleKeyUp() }
        )
        configureAssistantHotkeyManager()

        if !wasDownloading && !Transcriber.modelExists(modelSize: config.modelSize) {
            statusBar.state = .downloading
            statusBar.updateDownloadProgress("Downloading \(config.modelSize) model...")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    try ModelDownloader.download(modelSize: newConfig.modelSize) { percent in
                        DispatchQueue.main.async {
                            let pct = Int(percent)
                            self?.statusBar.updateDownloadProgress("Downloading \(newConfig.modelSize) model... \(pct)%", percent: percent)
                        }
                    }
                    DispatchQueue.main.async {
                        self?.statusBar.state = .idle
                        self?.statusBar.updateDownloadProgress(nil)
                    }
                } catch {
                    DispatchQueue.main.async {
                        print("Error downloading model: \(error.localizedDescription)")
                        self?.statusBar.state = .idle
                        self?.statusBar.updateDownloadProgress(nil)
                    }
                }
            }
        }

        statusBar.buildMenu()

        let hotkeyDesc = KeyCodes.describe(keyCode: config.hotkey.keyCode, modifiers: config.hotkey.modifiers)
        print("Config updated: lang=\(config.language) model=\(config.modelSize) hotkey=\(hotkeyDesc)")
    }

    private func handleKeyDown() {
        guard isReady else { return }
        guard !isMeetingCaptureActive, !isStoppingMeetingCapture else { return }
        guard captureMode == .none || captureMode == .dictation else { return }

        let isToggle = config.toggleMode?.value ?? false

        if isToggle {
            if isPressed, captureMode == .dictation {
                handleRecordingStop(mode: .dictation)
            } else {
                handleRecordingStart(mode: .dictation)
            }
        } else {
            guard !isPressed else { return }
            handleRecordingStart(mode: .dictation)
        }
    }

    private func handleKeyUp() {
        let isToggle = config.toggleMode?.value ?? false
        if isToggle { return }

        handleRecordingStop(mode: .dictation)
    }

    private func handleAssistantKeyDown() {
        guard isReady else { return }
        guard !isMeetingCaptureActive, !isStoppingMeetingCapture else { return }
        guard captureMode == .none || captureMode == .assistant else { return }

        let isToggle = config.toggleMode?.value ?? false
        if isToggle {
            if isPressed, captureMode == .assistant {
                handleRecordingStop(mode: .assistant)
            } else {
                handleRecordingStart(mode: .assistant)
            }
        } else {
            guard !isPressed else { return }
            handleRecordingStart(mode: .assistant)
        }
    }

    private func handleAssistantKeyUp() {
        let isToggle = config.toggleMode?.value ?? false
        if isToggle { return }
        handleRecordingStop(mode: .assistant)
    }

    private func handleRecordingStart(mode: CaptureMode) {
        guard !isPressed else { return }

        switch Permissions.ensureMicrophone() {
        case .granted:
            break
        case .denied:
            Permissions.openMicrophoneSettings()
            presentError("Enable Microphone permission before starting dictation")
            return
        }

        isPressed = true
        captureMode = mode
        statusBar.state = .recording
        do {
            let outputURL: URL
            if Config.effectiveMaxRecordings(config.maxRecordings) == 0 {
                outputURL = RecordingStore.tempRecordingURL()
            } else {
                outputURL = RecordingStore.newRecordingURL()
            }
            try recorder.startRecording(to: outputURL)
        } catch {
            print("Error: \(error.localizedDescription)")
            isPressed = false
            captureMode = .none
            statusBar.state = .idle
        }
    }

    private func handleRecordingStop(mode: CaptureMode) {
        guard isPressed else { return }
        guard captureMode == mode else { return }
        isPressed = false
        captureMode = .none

        guard let audioURL = recorder.stopRecording() else {
            statusBar.state = .idle
            return
        }

        statusBar.state = .transcribing

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let maxRecordings = Config.effectiveMaxRecordings(self.config.maxRecordings)
            defer {
                if maxRecordings == 0 {
                    try? FileManager.default.removeItem(at: audioURL)
                }
            }
            do {
                let raw = try self.transcriber.transcribe(audioURL: audioURL)
                let text = self.postProcess(raw)
                if maxRecordings > 0 {
                    RecordingStore.prune(maxCount: maxRecordings)
                }
                DispatchQueue.main.async {
                    switch mode {
                    case .dictation:
                        self.handleDictationTranscript(text)
                    case .assistant:
                        _ = self.handleAssistantTranscript(
                            text,
                            source: .assistantHotkey,
                            originalTranscript: text,
                            allowDictationFallback: false
                        )
                    case .none:
                        self.statusBar.state = .idle
                        self.statusBar.buildMenu()
                    }
                }
            } catch {
                if maxRecordings > 0 {
                    RecordingStore.prune(maxCount: maxRecordings)
                }
                DispatchQueue.main.async {
                    print("Error: \(error.localizedDescription)")
                    self.statusBar.state = .error(error.localizedDescription)
                    self.statusBar.buildMenu()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        if case .error = self.statusBar.state {
                            self.statusBar.state = .idle
                            self.statusBar.buildMenu()
                        }
                    }
                }
            }
        }
    }

    private func postProcess(_ raw: String) -> String {
        let punctuated = (config.spokenPunctuation?.value ?? false) ? TextPostProcessor.process(raw) : raw
        return DictionaryPostProcessor.process(punctuated, dictionary: config.customDictionary ?? [])
    }

    public func reprocess(audioURL: URL) {
        guard case .idle = statusBar.state else { return }

        statusBar.state = .transcribing

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let raw = try self.transcriber.transcribe(audioURL: audioURL)
                let text = self.postProcess(raw)
                DispatchQueue.main.async {
                    if !text.isEmpty {
                        self.lastTranscription = text
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        self.statusBar.state = .copiedToClipboard
                        self.statusBar.buildMenu()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self.statusBar.state = .idle
                            self.statusBar.buildMenu()
                        }
                    } else {
                        self.statusBar.state = .idle
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    print("Reprocess error: \(error.localizedDescription)")
                    self.statusBar.state = .idle
                }
            }
        }
    }

    func startMeetingCapture() {
        guard isReady, !isMeetingCaptureActive, !isStoppingMeetingCapture else { return }

        do {
            let directory = try TranscriptLogStore.validatedDirectory(path: config.meetingTranscriptDirectory)

            switch Permissions.ensureScreenCapture() {
            case .granted:
                break
            case .requiresRestart:
                presentError("Restart OpenWispr after granting Screen & System Audio Recording permission")
                return
            case .needsSystemSettings:
                Permissions.openScreenCaptureSettings()
                presentError("Use System Settings to enable Screen & System Audio Recording. If you just enabled it, restart OpenWispr.")
                return
            }

            let store = TranscriptLogStore(directory: directory)
            let session = try store.startSession(model: config.modelSize, language: config.language)
            let captureSession = SystemAudioCaptureSession()
            meetingTranscriptContext = ""
            meetingTranscriptSession = session
            captureSession.chunkReadyHandler = { [weak self] chunk in
                self?.processMeetingChunk(chunk)
            }
            captureSession.errorHandler = { [weak self] error in
                self?.handleMeetingCaptureError(error)
            }

            statusBar.state = .meetingStarting
            statusBar.buildMenu()

            captureSession.start { [weak self] error in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if let error {
                        try? session.finish(at: Date())
                        self.meetingTranscriptSession = nil
                        self.presentError(error.localizedDescription)
                        return
                    }

                    self.meetingCaptureSession = captureSession
                    self.isMeetingCaptureActive = true
                    self.isStoppingMeetingCapture = false
                    self.statusBar.state = .meetingRecording
                    self.statusBar.buildMenu()
                    print("Meeting capture started: \(session.fileURL.path)")
                }
            }
        } catch {
            presentError(error.localizedDescription)
        }
    }

    func stopMeetingCapture() {
        guard (isMeetingCaptureActive || meetingCaptureSession != nil), !isStoppingMeetingCapture else { return }

        isStoppingMeetingCapture = true
        statusBar.state = .meetingStopping
        statusBar.buildMenu()

        meetingCaptureSession?.stop { [weak self] stopError in
            guard let self = self else { return }
            self.meetingChunkQueue.async {
                self.meetingChunkGroup.wait()

                var finalError = stopError
                if let transcriptSession = self.meetingTranscriptSession {
                    do {
                        try transcriptSession.finish(at: Date())
                    } catch {
                        finalError = finalError ?? error
                    }
                }

                DispatchQueue.main.async {
                    self.meetingCaptureSession = nil
                    self.meetingTranscriptSession = nil
                    self.isMeetingCaptureActive = false
                    self.isStoppingMeetingCapture = false
                    self.meetingTranscriptContext = ""

                    if let finalError {
                        self.presentError(finalError.localizedDescription)
                    } else {
                        self.statusBar.state = .idle
                        self.statusBar.buildMenu()
                        print("Meeting capture stopped.")
                    }
                }
            }
        }
    }

    private func processMeetingChunk(_ chunk: SystemAudioChunk) {
        let group = meetingChunkGroup
        group.enter()
        meetingChunkQueue.async { [weak self] in
            defer {
                try? FileManager.default.removeItem(at: chunk.sourceURL)
                group.leave()
            }
            guard let self = self else { return }

            do {
                let convertedURL = try self.convertMeetingChunkToWhisperWav(chunk.sourceURL)
                defer { try? FileManager.default.removeItem(at: convertedURL) }

                let raw = try self.transcriber.transcribe(audioURL: convertedURL)
                let processed = self.postProcess(raw)
                let text = TranscriptOverlapResolver.trimCurrentText(
                    previousText: self.meetingTranscriptContext,
                    currentText: processed
                )
                guard !text.isEmpty else { return }

                try self.meetingTranscriptSession?.append(text: text, at: chunk.transcriptTimestamp)
                self.updateMeetingTranscriptContext(with: text)
                DispatchQueue.main.async {
                    self.statusBar.buildMenu()
                }
            } catch {
                DispatchQueue.main.async {
                    print("Meeting transcription error: \(error.localizedDescription)")
                    self.statusBar.buildMenu()
                }
            }
        }
    }

    private func convertMeetingChunkToWhisperWav(_ sourceURL: URL) throws -> URL {
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-wispr-meeting-\(UUID().uuidString).wav")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = [
            "-f", "WAVE",
            "-d", "LEI16@16000",
            "-c", "1",
            sourceURL.path,
            destinationURL.path,
        ]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw MeetingCaptureError.audioConversionFailed(stderr)
        }

        return destinationURL
    }

    private func handleMeetingCaptureError(_ error: Error) {
        DispatchQueue.main.async {
            print("Meeting capture error: \(error.localizedDescription)")
            if self.isMeetingCaptureActive || self.isStoppingMeetingCapture {
                self.presentError(error.localizedDescription)
            }
        }
    }

    func openMeetingTranscriptFolder() {
        do {
            let directory = try TranscriptLogStore.validatedDirectory(path: config.meetingTranscriptDirectory)
            NSWorkspace.shared.open(directory)
        } catch {
            presentError(error.localizedDescription)
        }
    }

    func openCurrentMeetingTranscript() {
        guard let url = currentMeetingTranscriptURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openAssistantDashboard() {
        let dashboard = AssistantDashboardWindowController.shared
        dashboard.reload()
        dashboard.showWindow(nil)
        dashboard.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentError(_ message: String) {
        print("Error: \(message)")
        statusBar.state = .error(message)
        statusBar.buildMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if case .error = self.statusBar.state {
                self.restoreStatusBarState()
                self.statusBar.buildMenu()
            }
        }
    }

    private func restoreStatusBarState() {
        if isStoppingMeetingCapture {
            statusBar.state = .meetingStopping
        } else if isMeetingCaptureActive {
            statusBar.state = .meetingRecording
        } else {
            statusBar.state = .idle
        }
    }

    private func handleDictationTranscript(_ text: String) {
        guard !text.isEmpty else {
            statusBar.state = .idle
            statusBar.buildMenu()
            return
        }

        let assistant = currentAssistantConfig()
        if assistant.isEnabled {
            if assistant.resolvedInvocationModes.contains(.wakePhrase),
               let stripped = assistantMatcher.stripWakePhrase(from: text, wakePhrase: assistant.resolvedWakePhrase) {
                _ = handleAssistantTranscript(
                    stripped,
                    source: .wakePhrase,
                    originalTranscript: text,
                    allowDictationFallback: false
                )
                return
            }

            if assistant.resolvedInvocationModes.contains(.intentDetect),
               handleAssistantTranscript(
                    text,
                    source: .intentDetect,
                    originalTranscript: text,
                    allowDictationFallback: true
               ) {
                return
            }
        }

        lastTranscription = text
        inserter.insert(text: text)
        statusBar.state = .idle
        statusBar.buildMenu()
    }

    @discardableResult
    private func handleAssistantTranscript(
        _ transcript: String,
        source: AssistantInvocationSource,
        originalTranscript: String,
        allowDictationFallback: Bool
    ) -> Bool {
        let assistant = currentAssistantConfig()
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard assistant.isEnabled || source == .dashboard else { return false }
        guard !trimmed.isEmpty else {
            statusBar.state = .idle
            statusBar.buildMenu()
            return source != .intentDetect || !allowDictationFallback
        }

        let skills = (try? assistantSkillStore.loadSkills(for: assistant)) ?? []
        let resolution = assistantMatcher.resolve(transcript: trimmed, skills: skills, source: source)
        switch resolution {
        case .none:
            if allowDictationFallback {
                return false
            }
            pendingAssistantRequest = nil
            AssistantDashboardWindowController.shared.presentDraft(
                input: originalTranscript,
                summary: "No matching skill. Edit or run from the dashboard.",
                requiresConfirmation: false
            )
            statusBar.state = .idle
            statusBar.buildMenu()
            return true
        case .matched(let request, let ambiguous):
            if shouldPreview(request: request, ambiguous: ambiguous) {
                pendingAssistantRequest = request
                AssistantDashboardWindowController.shared.presentDraft(
                    input: originalTranscript,
                    summary: assistantSummary(for: request, ambiguous: ambiguous),
                    requiresConfirmation: true
                )
                statusBar.state = .idle
                statusBar.buildMenu()
                return true
            }
            executeAssistantRequest(request)
            return true
        }
    }

    private func shouldPreview(request: SkillExecutionRequest, ambiguous: Bool) -> Bool {
        let assistant = currentAssistantConfig()
        if ambiguous { return true }
        if request.skill.kind == .codex { return true }
        if request.skill.requiresConfirmation { return true }
        if !request.skill.trusted { return true }
        return !assistant.shouldAutoRunDeterministicSkills
    }

    private func assistantSummary(for request: SkillExecutionRequest, ambiguous: Bool) -> String {
        if ambiguous {
            return "Ambiguous match for '\(request.input.isEmpty ? request.matchedTrigger : request.input)'. Confirm '\(request.skill.title)' before running."
        }
        if request.skill.kind == .codex {
            return "Codex task matched '\(request.skill.title)'. Review and confirm before running."
        }
        return "Skill matched: \(request.skill.title). Confirm to run."
    }

    private func executePendingAssistantRequest() {
        guard let request = pendingAssistantRequest else { return }
        pendingAssistantRequest = nil
        executeAssistantRequest(request)
    }

    private func executeAssistantRequest(_ request: SkillExecutionRequest) {
        statusBar.state = .transcribing
        statusBar.buildMenu()

        let assistantConfig = currentAssistantConfig()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try self.assistantExecutor.execute(
                    AssistantExecutionContext(
                        assistantConfig: assistantConfig,
                        request: request
                    )
                )
                try? self.assistantHistoryStore.append(result: result, for: assistantConfig)
                DispatchQueue.main.async {
                    self.routeAssistantOutput(result, outputMode: request.skill.effectiveOutputMode)
                    AssistantDashboardWindowController.shared.presentResult(result)
                    self.statusBar.state = .idle
                    self.statusBar.buildMenu()
                }
            } catch {
                DispatchQueue.main.async {
                    self.presentError(error.localizedDescription)
                    let failed = SkillExecutionResult(
                        skillID: request.skill.id,
                        skillTitle: request.skill.title,
                        kind: request.skill.kind,
                        source: request.source,
                        input: request.input,
                        matchedTrigger: request.matchedTrigger,
                        outputText: "",
                        standardError: error.localizedDescription,
                        exitCode: 1,
                        startedAt: Date(),
                        finishedAt: Date()
                    )
                    AssistantDashboardWindowController.shared.presentResult(failed)
                }
            }
        }
    }

    private func routeAssistantOutput(_ result: SkillExecutionResult, outputMode: AssistantOutputMode) {
        guard result.succeeded else { return }
        let output = result.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return }
        lastTranscription = output

        switch outputMode {
        case .dashboard, .none:
            break
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(output, forType: .string)
        case .insert:
            inserter.insert(text: output)
        }
    }

    private func currentAssistantConfig() -> AssistantConfig {
        config.assistant ?? AssistantConfig.defaultConfig
    }

    private func configureAssistantHotkeyManager() {
        assistantHotkeyManager?.stop()
        assistantHotkeyManager = nil

        let assistant = currentAssistantConfig()
        guard assistant.isEnabled,
              assistant.resolvedInvocationModes.contains(.assistantHotkey),
              let hotkey = assistant.hotkey else {
            return
        }

        assistantHotkeyManager = HotkeyManager(
            keyCode: hotkey.keyCode,
            modifiers: hotkey.modifierFlags
        )
        assistantHotkeyManager?.start(
            onKeyDown: { [weak self] in self?.handleAssistantKeyDown() },
            onKeyUp: { [weak self] in self?.handleAssistantKeyUp() }
        )
    }

    private func updateMeetingTranscriptContext(with text: String, maxTokens: Int = 64) {
        let combined = meetingTranscriptContext.isEmpty ? text : "\(meetingTranscriptContext) \(text)"
        let tokens = combined.split(whereSeparator: \.isWhitespace)
        meetingTranscriptContext = tokens.suffix(maxTokens).joined(separator: " ")
    }
}

enum MeetingCaptureError: LocalizedError {
    case audioConversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .audioConversionFailed(let details):
            return details.isEmpty ? "Failed to convert captured system audio" : "Failed to convert captured system audio: \(details)"
        }
    }
}
