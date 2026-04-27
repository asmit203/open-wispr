import AppKit

final class AssistantDashboardWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = AssistantDashboardWindowController()

    var executeTranscriptHandler: ((String) -> Void)?
    var executePendingHandler: (() -> Void)?
    var onConfigChange: ((Config) -> Void)?
    var onSkillsChanged: (() -> Void)?

    private let skillStore = AssistantSkillStore()
    private let historyStore = AssistantHistoryStore()

    private var skillTableView: NSTableView!
    private var skillEditorTextView: NSTextView!
    private var historyTextView: NSTextView!
    private var outputTextView: NSTextView!
    private var runInputField: NSSearchField!
    private var runSummaryLabel: NSTextField!
    private var runButton: NSButton!
    private var enabledCheckbox: NSButton!
    private var wakePhraseField: NSTextField!
    private var assistantHotkeyField: NSTextField!
    private var codexCommandField: NSTextField!
    private var codexArgsField: NSTextField!
    private var codexModelField: NSTextField!
    private var wakePhraseModeCheckbox: NSButton!
    private var assistantHotkeyModeCheckbox: NSButton!
    private var intentDetectCheckbox: NSButton!
    private var selectedSkill: SkillDefinition?
    private var loadedSkills: [SkillDefinition] = []
    private var awaitingConfirmation = false

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Assistant Dashboard"
        window.minSize = NSSize(width: 900, height: 620)
        window.center()

        super.init(window: window)
        setupUI()
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        reload()
        super.showWindow(sender)
    }

    func reload() {
        reloadRunTab()
        reloadSkills()
        reloadHistory()
        reloadSettings()
    }

    func presentDraft(input: String, summary: String, requiresConfirmation: Bool) {
        runInputField.stringValue = input
        runSummaryLabel.stringValue = summary
        awaitingConfirmation = requiresConfirmation
        runButton.title = requiresConfirmation ? "Confirm Run" : "Run"
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func presentResult(_ result: SkillExecutionResult) {
        let stderr = result.standardError.isEmpty ? "" : "\n\nstderr:\n\(result.standardError)"
        outputTextView.string = """
        Skill: \(result.skillTitle)
        Status: \(result.succeeded ? "Succeeded" : "Failed (\(result.exitCode))")
        Source: \(result.source.rawValue)
        Trigger: \(result.matchedTrigger)
        Input: \(result.input)

        Output:
        \(result.outputText)\(stderr)
        """
        reloadHistory()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func reloadRunTab() {
        if outputTextView.string.isEmpty {
            outputTextView.string = "Assistant results will appear here."
        }
        if runSummaryLabel.stringValue.isEmpty {
            runSummaryLabel.stringValue = "Type a command or trigger a voice command to preview it here."
        }
    }

    private func reloadSkills() {
        let assistantConfig = currentAssistantConfig()
        loadedSkills = (try? skillStore.loadSkills(for: assistantConfig)) ?? []
        if let selectedID = selectedSkill?.id {
            selectedSkill = loadedSkills.first(where: { $0.id == selectedID })
        } else if selectedSkill == nil {
            selectedSkill = loadedSkills.first
        }
        skillTableView?.reloadData()
        loadSelectedSkillIntoEditor()
    }

    private func reloadHistory() {
        let entries = historyStore.loadEntries(for: currentAssistantConfig())
        if entries.isEmpty {
            historyTextView.string = "No assistant runs yet."
            return
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        historyTextView.string = entries.map { entry in
            let timestamp = formatter.string(from: entry.timestamp)
            let status = entry.succeeded ? "OK" : "Failed"
            return "[\(timestamp)] \(entry.skillTitle) (\(entry.source.rawValue)) - \(status)\nInput: \(entry.input)\nPreview: \(entry.outputPreview)"
        }.joined(separator: "\n\n")
    }

    private func reloadSettings() {
        let assistant = currentAssistantConfig()
        enabledCheckbox.state = assistant.isEnabled ? .on : .off
        wakePhraseField.stringValue = assistant.resolvedWakePhrase
        assistantHotkeyField.stringValue = assistant.hotkey.map {
            KeyCodes.describe(keyCode: $0.keyCode, modifiers: $0.modifiers)
        } ?? ""
        codexCommandField.stringValue = assistant.codexRunner?.command ?? ""
        codexArgsField.stringValue = assistant.codexRunner?.args.joined(separator: " ") ?? ""
        codexModelField.stringValue = assistant.codexRunner?.model ?? ""

        let modes = assistant.resolvedInvocationModes
        wakePhraseModeCheckbox.state = modes.contains(.wakePhrase) ? .on : .off
        assistantHotkeyModeCheckbox.state = modes.contains(.assistantHotkey) ? .on : .off
        intentDetectCheckbox.state = modes.contains(.intentDetect) ? .on : .off
    }

    private func loadSelectedSkillIntoEditor() {
        guard let selectedSkill else {
            skillEditorTextView.string = newSkillMarkdown()
            return
        }
        skillEditorTextView.string = skillStore.renderMarkdown(for: selectedSkill)
    }

    private func setupUI() {
        guard let window else { return }

        let tabView = NSTabView(frame: window.contentView?.bounds ?? .zero)
        tabView.autoresizingMask = [.width, .height]

        tabView.addTabViewItem(runTab())
        tabView.addTabViewItem(skillsTab())
        tabView.addTabViewItem(historyTab())
        tabView.addTabViewItem(settingsTab())

        window.contentView = tabView
    }

    private func runTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "run")
        item.label = "Run"

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 620))

        runInputField = NSSearchField(frame: NSRect(x: 20, y: 570, width: 620, height: 28))
        view.addSubview(runInputField)

        runButton = NSButton(frame: NSRect(x: 660, y: 568, width: 120, height: 32))
        runButton.title = "Run"
        runButton.target = self
        runButton.action = #selector(runAssistantInput)
        view.addSubview(runButton)

        let reloadButton = NSButton(frame: NSRect(x: 800, y: 568, width: 120, height: 32))
        reloadButton.title = "Refresh"
        reloadButton.target = self
        reloadButton.action = #selector(refreshDashboard)
        view.addSubview(reloadButton)

        runSummaryLabel = NSTextField(labelWithString: "")
        runSummaryLabel.frame = NSRect(x: 20, y: 530, width: 900, height: 24)
        runSummaryLabel.lineBreakMode = .byWordWrapping
        view.addSubview(runSummaryLabel)

        outputTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 880, height: 500))
        outputTextView.isEditable = false
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: 900, height: 490))
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.documentView = outputTextView
        view.addSubview(scroll)

        item.view = view
        return item
    }

    private func skillsTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "skills")
        item.label = "Skills"

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 620))

        let listScroll = NSScrollView(frame: NSRect(x: 20, y: 60, width: 260, height: 540))
        listScroll.borderType = .bezelBorder
        listScroll.hasVerticalScroller = true

        skillTableView = NSTableView(frame: listScroll.bounds)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("skill"))
        column.title = "Skills"
        column.width = 240
        skillTableView.addTableColumn(column)
        skillTableView.delegate = self
        skillTableView.dataSource = self
        listScroll.documentView = skillTableView
        view.addSubview(listScroll)

        let newButton = NSButton(frame: NSRect(x: 20, y: 20, width: 80, height: 28))
        newButton.title = "New"
        newButton.target = self
        newButton.action = #selector(newSkill)
        view.addSubview(newButton)

        let deleteButton = NSButton(frame: NSRect(x: 110, y: 20, width: 80, height: 28))
        deleteButton.title = "Delete"
        deleteButton.target = self
        deleteButton.action = #selector(deleteSkill)
        view.addSubview(deleteButton)

        let saveButton = NSButton(frame: NSRect(x: 200, y: 20, width: 80, height: 28))
        saveButton.title = "Save"
        saveButton.target = self
        saveButton.action = #selector(saveSkill)
        view.addSubview(saveButton)

        skillEditorTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 580))
        let editorScroll = NSScrollView(frame: NSRect(x: 300, y: 20, width: 620, height: 580))
        editorScroll.borderType = .bezelBorder
        editorScroll.hasVerticalScroller = true
        editorScroll.documentView = skillEditorTextView
        view.addSubview(editorScroll)

        item.view = view
        return item
    }

    private func historyTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "history")
        item.label = "History"

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 620))
        historyTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 880, height: 580))
        historyTextView.isEditable = false
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: 900, height: 580))
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.documentView = historyTextView
        view.addSubview(scroll)

        item.view = view
        return item
    }

    private func settingsTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "settings")
        item.label = "Settings"

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 620))

        enabledCheckbox = checkbox(title: "Enable Assistant", x: 20, y: 560)
        wakePhraseModeCheckbox = checkbox(title: "Wake Phrase Mode", x: 20, y: 520)
        assistantHotkeyModeCheckbox = checkbox(title: "Assistant Hotkey Mode", x: 20, y: 490)
        intentDetectCheckbox = checkbox(title: "Intent Detect Mode", x: 20, y: 460)

        view.addSubview(enabledCheckbox)
        view.addSubview(wakePhraseModeCheckbox)
        view.addSubview(assistantHotkeyModeCheckbox)
        view.addSubview(intentDetectCheckbox)

        view.addSubview(label("Wake Phrase", x: 20, y: 420))
        wakePhraseField = textField(x: 180, y: 416, width: 300)
        view.addSubview(wakePhraseField)

        view.addSubview(label("Assistant Hotkey", x: 20, y: 380))
        assistantHotkeyField = textField(x: 180, y: 376, width: 300)
        assistantHotkeyField.placeholderString = "cmd+shift+k"
        view.addSubview(assistantHotkeyField)

        view.addSubview(label("Codex Command", x: 20, y: 330))
        codexCommandField = textField(x: 180, y: 326, width: 500)
        view.addSubview(codexCommandField)

        view.addSubview(label("Codex Args", x: 20, y: 290))
        codexArgsField = textField(x: 180, y: 286, width: 700)
        codexArgsField.placeholderString = "run --json"
        view.addSubview(codexArgsField)

        view.addSubview(label("Codex Model", x: 20, y: 250))
        codexModelField = textField(x: 180, y: 246, width: 300)
        view.addSubview(codexModelField)

        let saveButton = NSButton(frame: NSRect(x: 20, y: 190, width: 140, height: 32))
        saveButton.title = "Save Settings"
        saveButton.target = self
        saveButton.action = #selector(saveSettings)
        view.addSubview(saveButton)

        item.view = view
        return item
    }

    private func checkbox(title: String, x: CGFloat, y: CGFloat) -> NSButton {
        let button = NSButton(frame: NSRect(x: x, y: y, width: 260, height: 24))
        button.setButtonType(.switch)
        button.title = title
        return button
    }

    private func label(_ text: String, x: CGFloat, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: x, y: y, width: 140, height: 24)
        return label
    }

    private func textField(x: CGFloat, y: CGFloat, width: CGFloat) -> NSTextField {
        NSTextField(frame: NSRect(x: x, y: y, width: width, height: 24))
    }

    private func currentAssistantConfig() -> AssistantConfig {
        Config.load().assistant ?? AssistantConfig.defaultConfig
    }

    private func newSkillMarkdown() -> String {
        """
        ---
        id: sample-skill
        title: Sample Skill
        description: Example assistant skill
        kind: shell
        enabled: true
        triggers: ["sample task"]
        requiresConfirmation: false
        outputMode: dashboard
        command: /bin/echo
        args: []
        passTranscriptAs: finalArg
        trusted: false
        ---

        Replace this with the instructions or notes for the skill.
        """
    }

    @objc private func runAssistantInput() {
        if awaitingConfirmation {
            executePendingHandler?()
            awaitingConfirmation = false
            runButton.title = "Run"
            return
        }
        let input = runInputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        executeTranscriptHandler?(input)
    }

    @objc private func refreshDashboard() {
        reload()
    }

    @objc private func newSkill() {
        selectedSkill = nil
        skillEditorTextView.string = newSkillMarkdown()
    }

    @objc private func deleteSkill() {
        guard let selectedSkill else { return }
        try? skillStore.deleteSkill(selectedSkill)
        self.selectedSkill = nil
        onSkillsChanged?()
        reloadSkills()
    }

    @objc private func saveSkill() {
        do {
            let saved = try skillStore.saveSkill(
                markdown: skillEditorTextView.string,
                existingURL: selectedSkill?.sourceURL,
                for: currentAssistantConfig()
            )
            selectedSkill = saved
            onSkillsChanged?()
            reloadSkills()
        } catch {
            runSummaryLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func saveSettings() {
        var config = Config.load()
        var assistant = config.assistant ?? AssistantConfig.defaultConfig
        assistant.enabled = enabledCheckbox.state == .on

        var modes: [AssistantInvocationMode] = []
        if wakePhraseModeCheckbox.state == .on { modes.append(.wakePhrase) }
        if assistantHotkeyModeCheckbox.state == .on { modes.append(.assistantHotkey) }
        if intentDetectCheckbox.state == .on { modes.append(.intentDetect) }
        assistant.invocationModes = modes
        assistant.intentDetectEnabled = modes.contains(.intentDetect)

        let wakePhrase = wakePhraseField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        assistant.wakePhrase = wakePhrase.isEmpty ? AssistantConfig.defaultConfig.resolvedWakePhrase : wakePhrase

        let hotkeyInput = assistantHotkeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if hotkeyInput.isEmpty {
            assistant.hotkey = nil
        } else if let parsed = KeyCodes.parse(hotkeyInput) {
            assistant.hotkey = HotkeyConfig(keyCode: parsed.keyCode, modifiers: parsed.modifiers)
        }

        let command = codexCommandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let args = codexArgsField.stringValue
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        let model = codexModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if command.isEmpty {
            assistant.codexRunner = nil
        } else {
            assistant.codexRunner = CodexRunnerConfig(
                command: command,
                args: args,
                model: model.isEmpty ? nil : model,
                workingDirectory: nil,
                includeTranscriptInArgs: true,
                timeoutSeconds: 120
            )
        }

        config.assistant = assistant
        do {
            try config.save()
            onConfigChange?(config)
        } catch {
            runSummaryLabel.stringValue = error.localizedDescription
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        loadedSkills.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < loadedSkills.count else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("SkillCell")
        let view = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        view.identifier = identifier
        if view.textField == nil {
            let textField = NSTextField(labelWithString: "")
            textField.frame = NSRect(x: 4, y: 1, width: tableView.bounds.width - 8, height: 20)
            textField.autoresizingMask = [.width]
            view.textField = textField
            view.addSubview(textField)
        }
        view.textField?.stringValue = loadedSkills[row].title
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = skillTableView.selectedRow
        guard row >= 0, row < loadedSkills.count else { return }
        selectedSkill = loadedSkills[row]
        loadSelectedSkillIntoEditor()
    }
}
