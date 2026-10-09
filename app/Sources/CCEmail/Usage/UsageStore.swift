import AppKit
import CCEmailCore
import Foundation
import Observation

/// Plan limits and the model list, as reported by Claude Code.
///
/// Everything comes from Claude Code's own control requests (`get_usage`, `list_models`), which
/// make no model call; Claude Code fetches plan limits with its own login. The app never reads
/// credentials or calls an API itself.
@Observable @MainActor
final class UsageStore {
    private(set) var plan: PlanUsage? {
        didSet { save(plan, key: "planUsage") }
    }
    private(set) var models: [ModelOption] {
        didSet { save(models, key: "models") }
    }
    private(set) var refreshing = false

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var probing = false

    static let refreshInterval: TimeInterval = 5 * 60

    init() {
        plan = Self.load(PlanUsage.self, key: "planUsage")
        models = Self.load([ModelOption].self, key: "models") ?? ModelCatalog.fallback
    }

    func update(_ usage: PlanUsage) { plan = usage }

    func update(_ options: [ModelOption]) {
        if !options.isEmpty { models = options }
    }

    /// Refreshes plan usage through the active conversation's running claude, or a short-lived
    /// probe process when none is running.
    func refresh(context: LaunchContext?, conversations: ConversationStore) {
        if let live = conversations.liveActive {
            live.requestUsage()
            return
        }
        guard let context, !probing else { return }
        probing = true
        refreshing = true
        Task {
            let result = await UsageProbe.run(context: context)
            if let plan = result.plan { self.plan = plan }
            if let models = result.models {
                self.update(models)
                conversations.needsModelList = false
            }
            probing = false
            refreshing = false
        }
    }

    /// Refreshes every few minutes while the app is in front, like a status line.
    func startTimer(context: @escaping () -> LaunchContext?, conversations: ConversationStore) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard NSApp.isActive else { return }
                self?.refresh(context: context(), conversations: conversations)
            }
        }
    }

    private func save<T: Encodable>(_ value: T?, key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// Starts claude just long enough to ask for plan usage and the model list, then stops it.
/// It sends no user message, so there is no model call; no MCP servers and no tools are loaded.
enum UsageProbe {
    struct Result {
        var plan: PlanUsage?
        var models: [ModelOption]?
    }

    static func run(context: LaunchContext, timeout: TimeInterval = 30) async -> Result {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ccemail-usage-probe")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var config = LaunchConfig(
            claudePath: context.claudePath, workingDirectory: directory, sessionId: "", resume: false,
            appendSystemPrompt: nil, allowedTools: [], includePartialMessages: false, path: context.path
        )
        config.extraArguments = ["--strict-mcp-config", "--tools", ""]

        // Same rule as conversations: only ever run on the Claude Code login.
        let auth = await Task.detached { ClaudeLocator.authStatus(for: config) }.value
        guard auth?.usesClaudeCodeLogin == true else { return Result() }

        let process = ClaudeProcess(config: config)
        do { try process.start() } catch { return Result() }
        defer { process.terminate() }

        let usageId = process.makeRequestId()
        let modelsId = process.makeRequestId()
        process.send(Outbound.initialize(requestId: process.makeRequestId()))
        process.send(Outbound.getUsage(requestId: usageId))
        process.send(Outbound.listModels(requestId: modelsId))

        var result = Result()
        var answered = Set<String>()
        let deadline = Task {
            try? await Task.sleep(for: .seconds(timeout))
            process.terminate()
        }
        defer { deadline.cancel() }

        for await output in process.output {
            guard case .event(.controlResponse(let id, let success, let payload, _)) = output else { continue }
            if id == usageId {
                answered.insert(id)
                if success, let payload { result.plan = PlanUsage(response: payload) }
            } else if id == modelsId {
                answered.insert(id)
                if success, let payload { result.models = ModelCatalog.options(fromListModels: payload) }
            }
            if answered.count == 2 { break }
        }
        return result
    }
}
