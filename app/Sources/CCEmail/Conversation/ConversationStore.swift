import CCEmailCore
import Foundation
import Observation

/// All conversations, the active one, and their transcripts on disk.
/// Transcripts can contain email content, so they live in Application Support, never in the repo.
@Observable @MainActor
final class ConversationStore {
    nonisolated static let defaultTitle = "New conversation"

    private(set) var conversations: [Conversation] = []
    var activeID: UUID?

    @ObservationIgnored let contextProvider: () -> LaunchContext?
    @ObservationIgnored var labelNames: () -> LabelNames = { LabelNames() }
    @ObservationIgnored var onPlanUsage: (PlanUsage) -> Void = { _ in }
    @ObservationIgnored var onModels: ([ModelOption]) -> Void = { _ in }
    @ObservationIgnored var needsModelList = true
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(contextProvider: @escaping () -> LaunchContext?) {
        self.contextProvider = contextProvider
        load()
        // Each launch starts fresh; earlier conversations stay in the sidebar.
        newConversation()
    }

    var active: Conversation? {
        conversations.first { $0.id == activeID }
    }

    var sorted: [Conversation] {
        conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    var anyBusy: Bool { conversations.contains(where: \.isBusy) }

    /// The first open permission prompt or question in any conversation.
    var nextPrompt: PromptRef? {
        for conversation in conversations {
            if let request = conversation.pendingPermissions.first {
                return PromptRef(conversation: conversation, request: request)
            }
        }
        return nil
    }

    @discardableResult
    func newConversation(title: String = defaultTitle) -> Conversation {
        let conversation = Conversation(title: title)
        conversation.store = self
        conversations.append(conversation)
        activate(conversation)
        scheduleSave()
        return conversation
    }

    /// Starts a fresh conversation in place of `conversation`, which stays in the sidebar.
    /// Does nothing if it's busy or already empty.
    func clear(_ conversation: Conversation) {
        guard !conversation.isBusy, !conversation.items.isEmpty else { return }
        newConversation()
    }

    func activate(_ conversation: Conversation) {
        activeID = conversation.id
        // Keep at most one idle process: stop the others' until they're needed again.
        for other in conversations where other.id != conversation.id && !other.isBusy && other.hasLiveProcess {
            other.shutdown()
        }
    }

    /// Sends `text` in the active conversation if it's free, otherwise in a new one.
    /// Used by the Summary and Drafts views' buttons.
    @discardableResult
    func send(_ text: String, title: String) -> Conversation {
        let target: Conversation
        if let active, !active.isBusy {
            target = active
        } else {
            target = newConversation(title: title)
        }
        activate(target)
        target.send(text)
        return target
    }

    func delete(_ conversation: Conversation) {
        conversation.shutdown()
        conversations.removeAll { $0.id == conversation.id }
        if activeID == conversation.id { activeID = sorted.first?.id }
        scheduleSave()
    }

    func shutdownAll() {
        for conversation in conversations { conversation.shutdown() }
        saveNow()
    }

    /// The active conversation if its claude process is running, for control requests.
    var liveActive: Conversation? {
        guard let active, active.hasLiveProcess else { return nil }
        return active
    }

    /// Switches every running session to `model`; new sessions start with it.
    func applyModel(_ model: String) {
        for conversation in conversations where conversation.hasLiveProcess {
            conversation.setModel(model)
        }
    }

    // MARK: Callbacks from conversations

    func planUsageUpdated(_ usage: PlanUsage) { onPlanUsage(usage) }

    func modelsUpdated(_ models: [ModelOption]) {
        needsModelList = false
        onModels(models)
    }

    func changed(_ conversation: Conversation) {
        scheduleSave()
    }

    func turnFinished(_ conversation: Conversation) {
        if conversation.id != activeID { conversation.shutdown() }
        scheduleSave()
    }

    // MARK: Persistence

    private struct Record: Codable {
        var id: UUID
        var title: String
        var createdAt: Date
        var updatedAt: Date
        var hasSession: Bool
        var items: [TranscriptItem]
    }

    private static var fileURL: URL {
        // CCEMAIL_DATA_DIR keeps development runs (see DevHooks) out of the real transcripts.
        if let dir = ProcessInfo.processInfo.environment["CCEMAIL_DATA_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir).appendingPathComponent("conversations.json")
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CC Email", isDirectory: true).appendingPathComponent("conversations.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let records = try? decoder.decode([Record].self, from: data) else { return }
        // Empty conversations were never used, so there's nothing to bring back.
        conversations = records.filter { !$0.items.isEmpty }.map { record in
            let conversation = Conversation(
                id: record.id, title: record.title, createdAt: record.createdAt,
                items: record.items, hasSession: record.hasSession
            )
            conversation.updatedAt = record.updatedAt
            conversation.store = self
            return conversation
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let records = conversations.filter { !$0.items.isEmpty }.map { c in
            // Tool rows that were running when saved can't still be running when reloaded.
            let items = c.items.map { item -> TranscriptItem in
                var item = item
                if item.toolStatus == .running, !c.isBusy { item.toolStatus = .done }
                return item
            }
            return Record(id: c.id, title: c.title, createdAt: c.createdAt, updatedAt: c.updatedAt,
                          hasSession: c.hasSession, items: items)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }
}

struct PromptRef: Identifiable {
    var conversation: Conversation
    var request: PermissionRequest
    var id: String { "\(conversation.id)-\(request.requestId)" }
}
