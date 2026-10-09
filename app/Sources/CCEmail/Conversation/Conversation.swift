import AppKit
import CCEmailCore
import Foundation
import Observation

/// One chat with Claude Code, backed by a long-running `claude -p` process while it's active.
/// The process is stopped when the conversation goes idle in the background and is
/// restarted with `--resume` when the user sends another message.
@Observable @MainActor
final class Conversation: Identifiable {
    enum State: Equatable {
        case idle
        case starting
        case running
        case failed(String)
    }

    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var items: [TranscriptItem]
    /// True once claude has created the session, so later processes use `--resume`.
    var hasSession: Bool
    var state: State = .idle
    var pendingPermissions: [PermissionRequest] = []
    var sessionInfo: SessionInfo?
    /// How full this session's context window is, refreshed after each turn.
    var contextUsage: ContextUsage?

    @ObservationIgnored weak var store: ConversationStore?
    @ObservationIgnored private var process: ClaudeProcess?
    @ObservationIgnored private var stopRequested = false
    @ObservationIgnored private var terminating = false
    @ObservationIgnored private var liveTextIndex: Int?
    @ObservationIgnored private var answeredToolUseIds = Set<String>()
    @ObservationIgnored private var warnedAboutGmail = false
    /// Control requests the app sent and is waiting on, by request ID.
    @ObservationIgnored private var pendingControl: [String: ControlKind] = [:]

    private enum ControlKind { case contextUsage, planUsage, listModels, setModel }

    var sessionId: String { id.uuidString.lowercased() }
    var isBusy: Bool { state == .starting || state == .running }
    var hasLiveProcess: Bool { process?.isRunning == true }

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), items: [TranscriptItem] = [], hasSession: Bool = false) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.items = items
        self.hasSession = hasSession
    }

    // MARK: Sending

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        if items.isEmpty, title == ConversationStore.defaultTitle {
            title = String(text.prefix(60))
        }
        items.append(TranscriptItem(kind: .user, text: text))
        updatedAt = Date()
        stopRequested = false
        liveTextIndex = nil
        state = .starting
        store?.changed(self)
        Task { await deliver(text) }
    }

    private func deliver(_ text: String) async {
        if process?.isRunning != true {
            guard await startProcess() else { return }
        }
        if stopRequested {  // Stop was pressed while the process was starting
            stopRequested = false
            note("Stopped.", isError: false)
            state = .idle
            store?.turnFinished(self)
            return
        }
        state = .running
        process?.send(Outbound.userMessage(text, sessionId: sessionId))
    }

    /// Starts claude for this conversation. Refuses unless claude would run on the user's
    /// Claude Code login: the app must never spend API-key or other paid usage.
    private func startProcess() async -> Bool {
        guard let context = store?.contextProvider() else {
            fail("Claude Code isn't ready. Check the banner at the top of the window or Settings.")
            return false
        }
        let config = LaunchConfig(
            claudePath: context.claudePath,
            workingDirectory: context.repoURL,
            sessionId: sessionId,
            resume: hasSession,
            model: context.model,
            includePartialMessages: context.streamReplies,
            path: context.path
        )
        let auth = await Task.detached { ClaudeLocator.authStatus(for: config) }.value
        guard let auth, auth.usesClaudeCodeLogin else {
            fail("Not started: Claude Code would use \(auth?.authMethod ?? "an unknown login") instead of your Claude Code login.")
            return false
        }

        let process = ClaudeProcess(config: config)
        do {
            try process.start()
        } catch {
            fail("Couldn't start claude: \(error.localizedDescription)")
            return false
        }
        self.process = process
        terminating = false
        warnedAboutGmail = false
        process.send(Outbound.initialize(requestId: process.makeRequestId()))
        Task { [weak self] in
            for await output in process.output {
                self?.handle(output, from: process)
            }
        }
        return true
    }

    // MARK: Controls

    func stop() {
        guard isBusy else { return }
        stopRequested = true
        guard state == .running else { return }
        // Answer any open prompt first, or the interrupt can't land.
        for request in pendingPermissions {
            process?.send(Outbound.deny(requestId: request.requestId, toolUseId: request.toolUseId, message: "The user stopped the turn."))
        }
        pendingPermissions.removeAll()
        process?.interrupt()
    }

    /// Ends the process. The conversation can continue later with `--resume`.
    func shutdown() {
        guard let process else { return }
        terminating = true
        pendingPermissions.removeAll()
        process.terminate()
    }

    /// Asks the running claude for context and plan usage. Control requests only: no model call.
    func requestUsage() {
        sendControl(.contextUsage)
        sendControl(.planUsage)
    }

    /// Switches the running session's model; it takes effect from the next turn.
    func setModel(_ model: String) {
        sendControl(.setModel, model: model)
    }

    private func sendControl(_ kind: ControlKind, model: String? = nil) {
        guard let process, process.isRunning else { return }
        let id = process.makeRequestId()
        pendingControl[id] = kind
        switch kind {
        case .contextUsage: process.send(Outbound.getContextUsage(requestId: id))
        case .planUsage: process.send(Outbound.getUsage(requestId: id))
        case .listModels: process.send(Outbound.listModels(requestId: id))
        case .setModel: process.send(Outbound.setModel(model ?? "", requestId: id))
        }
    }

    func allow(_ request: PermissionRequest, forConversation: Bool = false) {
        var updates: [JSONValue] = []
        if forConversation {
            // Keep "always allow" scoped to this session; never write it to the settings files.
            updates = request.suggestions.map { suggestion in
                var dict = suggestion.objectValue ?? [:]
                dict["destination"] = "session"
                return .object(dict)
            }
        }
        respond(to: request, Outbound.allow(
            requestId: request.requestId, toolUseId: request.toolUseId,
            updatedInput: request.input, updatedPermissions: updates
        ))
    }

    func deny(_ request: PermissionRequest) {
        respond(to: request, Outbound.deny(
            requestId: request.requestId, toolUseId: request.toolUseId,
            message: "The user denied this in the CC Email app."
        ))
    }

    func answer(_ request: PermissionRequest, answers: [String: String]) {
        respond(to: request, Outbound.allow(
            requestId: request.requestId, toolUseId: request.toolUseId,
            updatedInput: Outbound.answeredQuestions(input: request.input, answers: answers)
        ))
    }

    func dismissQuestion(_ request: PermissionRequest) {
        respond(to: request, Outbound.deny(
            requestId: request.requestId, toolUseId: request.toolUseId,
            message: "The user dismissed the question without answering."
        ))
    }

    private func respond(to request: PermissionRequest, _ message: JSONValue) {
        pendingPermissions.removeAll { $0.requestId == request.requestId }
        if let id = request.toolUseId { answeredToolUseIds.insert(id) }
        process?.send(message)
    }

    // MARK: Events

    private func handle(_ output: ProcessOutput, from source: ClaudeProcess) {
        guard source === process else { return }  // a stale process from before a restart
        switch output {
        case .event(let event):
            handle(event)
        case .exited(let status, let stderrTail):
            process = nil
            pendingPermissions.removeAll()
            pendingControl.removeAll()
            liveTextIndex = nil
            if stderrTail.contains("already in use") { hasSession = true }
            if terminating || state == .idle {
                if case .failed = state {} else { state = .idle }
            } else {
                let tail = stderrTail.split(separator: "\n").suffix(6).joined(separator: "\n")
                fail("Claude Code stopped unexpectedly (exit \(status)).\(tail.isEmpty ? "" : "\n\n```\n\(tail)\n```")")
            }
            store?.changed(self)
        }
    }

    private func handle(_ event: StreamEvent) {
        let labels = store?.labelNames() ?? LabelNames()
        switch event {
        case .initialized(let info):
            sessionInfo = info
            hasSession = true
            guard info.usesClaudeCodeLogin else {
                // Second line of defence after the auth preflight.
                fail("Stopped: this session reported credentials from \(info.apiKeySource), not your Claude Code login.")
                shutdown()
                return
            }
            if !warnedAboutGmail {
                warnedAboutGmail = true
                // claude.ai connectors finish connecting in the background, so "pending" at
                // startup is normal. Only a missing or failed connector is worth a warning.
                let gmail = info.mcpServers.first { $0.name.localizedCaseInsensitiveContains("gmail") }
                if let status = gmail?.status, ["connected", "pending"].contains(status) {
                    // fine
                } else {
                    note("The Gmail connector is \(gmail?.status ?? "missing") in Claude Code, so mail tools may not work.", isError: true)
                }
                if store?.needsModelList == true { sendControl(.listModels) }
            }

        case .textDelta(let text, let parent):
            guard parent == nil else { return }
            if let index = liveTextIndex, items.indices.contains(index) {
                items[index].text += text
            } else {
                items.append(TranscriptItem(kind: .assistant, text: text))
                liveTextIndex = items.count - 1
            }

        case .assistant(let message):
            if let parent = message.parentToolUseId {
                recordSubagentActivity(message, parent: parent)
                return
            }
            for block in message.blocks {
                switch block {
                case .text(let text):
                    if let index = liveTextIndex, items.indices.contains(index) {
                        items[index].text = text
                        liveTextIndex = nil
                    } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        items.append(TranscriptItem(kind: .assistant, text: text))
                    }
                case .toolUse(let id, let name, let input):
                    liveTextIndex = nil
                    items.append(TranscriptItem(
                        kind: .tool, text: ToolDisplay.summary(name: name, input: input, labels: labels),
                        toolName: name, toolUseId: id, toolStatus: .running
                    ))
                default:
                    break
                }
            }
            if let error = message.error { note("Claude Code reported: \(error)", isError: true) }

        case .toolResults(let results, let parent):
            guard parent == nil else { return }
            for result in results {
                guard let index = items.lastIndex(where: { $0.toolUseId == result.toolUseId }) else { continue }
                items[index].toolStatus = result.isError ? .failed : .done
                if result.isError {
                    items[index].detail = labels.humanize(String(result.text.prefix(300)))
                }
            }

        case .permissionRequest(let request):
            pendingPermissions.append(request)
            if !NSApp.isActive { NSApp.requestUserAttention(.criticalRequest) }

        case .controlCancel(let requestId):
            pendingPermissions.removeAll { $0.requestId == requestId }

        case .unsupportedControlRequest(let requestId, let subtype):
            process?.send(Outbound.controlError(requestId: requestId, message: "CC Email doesn't support \(subtype)."))

        case .permissionDenied(let toolName, let message):
            note("Claude Code blocked \(ToolDisplay.name(toolName))\(message.isEmpty ? "" : ": \(message)")", isError: false)

        case .result(let result):
            finishTurn(result)

        case .controlResponse(let requestId, let success, let payload, _):
            guard let kind = pendingControl.removeValue(forKey: requestId), success, let payload else { break }
            switch kind {
            case .contextUsage:
                if let usage = ContextUsage(response: payload) { contextUsage = usage }
            case .planUsage:
                if let usage = PlanUsage(response: payload) { store?.planUsageUpdated(usage) }
            case .listModels:
                store?.modelsUpdated(ModelCatalog.options(fromListModels: payload))
            case .setModel:
                break
            }

        case .other, .unparsable:
            break
        }
        store?.changed(self)
    }

    private func recordSubagentActivity(_ message: AssistantMessage, parent: String) {
        guard let index = items.lastIndex(where: { $0.toolUseId == parent }) else { return }
        for case .toolUse(_, let name, _) in message.blocks {
            items[index].childCount += 1
            items[index].childActivity = ToolDisplay.name(name)
        }
    }

    private func finishTurn(_ result: TurnResult) {
        liveTextIndex = nil
        pendingPermissions.removeAll()
        // Tools still marked running didn't finish (e.g. the turn was stopped).
        for index in items.indices where items[index].toolStatus == .running {
            items[index].toolStatus = stopRequested ? .failed : .done
        }
        if stopRequested {
            note("Stopped.", isError: false)
        } else if result.isError {
            let detail = result.errors.first ?? result.resultText ?? result.subtype
            note("The turn ended with an error: \(detail)", isError: true)
        }
        // Denials the user didn't make here (e.g. a deny rule in settings) are worth knowing about.
        for denial in result.permissionDenials where !answeredToolUseIds.contains(denial.toolUseId ?? "") {
            note("Claude Code blocked \(ToolDisplay.name(denial.toolName)).", isError: false)
        }
        answeredToolUseIds.removeAll()
        stopRequested = false
        state = .idle
        updatedAt = Date()
        requestUsage()
        store?.turnFinished(self)
    }

    private func note(_ text: String, isError: Bool) {
        items.append(TranscriptItem(kind: isError ? .error : .notice, text: text))
    }

    private func fail(_ message: String) {
        state = .failed(message)
        note(message, isError: true)
        store?.changed(self)
    }
}
