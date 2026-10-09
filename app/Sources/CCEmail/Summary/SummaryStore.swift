import CCEmailCore
import Foundation
import Observation

/// `inbox-summary.md` and the user's unsaved edits to it.
///
/// The file on disk is the source of truth; Claude rewrites it during /summary and when applying
/// notes. The user's ticks and notes are kept as edits on top of the last copy read from disk,
/// saved after a short pause, and re-applied onto any newer copy (matched by thread ID).
@Observable @MainActor
final class SummaryStore {
    private(set) var document: SummaryDocument?
    private(set) var fileExists = false
    private(set) var conflicts: [SummaryConflict] = []
    private(set) var saveError: String?

    @ObservationIgnored private let conversations: ConversationStore
    @ObservationIgnored private var url: URL?
    @ObservationIgnored private var diskText = ""
    @ObservationIgnored private var lastWrittenHash: String?
    @ObservationIgnored private var pendingEdits: [SummaryEdit] = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(conversations: ConversationStore) {
        self.conversations = conversations
    }

    /// Editing is paused while Claude is working, since it may be rewriting the file.
    var isLocked: Bool { conversations.anyBusy }
    var hasUnsavedEdits: Bool { !pendingEdits.isEmpty }

    func open(repo: URL) {
        url = repo.appendingPathComponent("inbox-summary.md")
        reload()
    }

    func fileChanged() {
        guard let url, let text = try? FileIO.read(url) else {
            reload()
            return
        }
        if FileIO.hash(text) == lastWrittenHash { return }  // our own save
        reload()
    }

    func reload() {
        guard let url else { return }
        if let text = try? FileIO.read(url) {
            fileExists = true
            diskText = text
        } else {
            fileExists = false
            diskText = ""
        }
        rebuild()
    }

    /// The document as shown: the disk copy with pending edits applied.
    private func rebuild() {
        guard fileExists else {
            document = nil
            return
        }
        let (text, newConflicts) = SummaryPatcher.apply(pendingEdits, to: diskText)
        if !newConflicts.isEmpty {
            conflicts += newConflicts
            let failed = Set(newConflicts.map(\.edit))
            pendingEdits.removeAll { failed.contains($0) }
        }
        document = SummaryParser.parse(text)
    }

    // MARK: Edits

    func setChecked(_ item: SummaryItem, action: ActionLine, to checked: Bool) {
        let edit = SummaryEdit.setChecked(
            threadId: item.threadId, kind: action.kind, ordinal: action.ordinal, from: action.checked, to: checked
        )
        record(edit)
        scheduleSave(after: .milliseconds(400))
    }

    func setNotes(_ item: SummaryItem, to text: String) {
        let current = item.notes?.text ?? ""
        guard SummaryPatcher.normalizedNotes(text) != current else { return }
        record(.setNotes(threadId: item.threadId, from: current, to: text))
        scheduleSave(after: .seconds(1))
    }

    /// Merges with an earlier edit to the same target, keeping the earliest "from" value.
    private func record(_ edit: SummaryEdit) {
        switch edit {
        case .setChecked(let id, let kind, let ordinal, _, let to):
            if let i = pendingEdits.firstIndex(where: {
                if case .setChecked(id, kind, ordinal, _, _) = $0 { return true } else { return false }
            }), case .setChecked(_, _, _, let originalFrom, _) = pendingEdits[i] {
                pendingEdits.remove(at: i)
                if originalFrom != to {
                    pendingEdits.append(.setChecked(threadId: id, kind: kind, ordinal: ordinal, from: originalFrom, to: to))
                }
            } else {
                pendingEdits.append(edit)
            }
        case .setNotes(let id, _, let to):
            if let i = pendingEdits.firstIndex(where: {
                if case .setNotes(id, _, _) = $0 { return true } else { return false }
            }), case .setNotes(_, let originalFrom, _) = pendingEdits[i] {
                pendingEdits.remove(at: i)
                if SummaryPatcher.normalizedNotes(originalFrom) != SummaryPatcher.normalizedNotes(to) {
                    pendingEdits.append(.setNotes(threadId: id, from: originalFrom, to: to))
                }
            } else {
                pendingEdits.append(edit)
            }
        }
        rebuild()
    }

    private func scheduleSave(after delay: Duration) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Writes pending edits onto the current disk copy. Returns false if the write failed.
    @discardableResult
    func save() -> Bool {
        saveTask?.cancel()
        guard let url, !pendingEdits.isEmpty else { return true }
        let current = (try? FileIO.read(url)) ?? diskText
        let (text, newConflicts) = SummaryPatcher.apply(pendingEdits, to: current)
        do {
            if text != current {
                lastWrittenHash = FileIO.hash(text)
                try FileIO.writeAtomically(text, to: url)
            }
            diskText = text
            pendingEdits.removeAll()
            conflicts += newConflicts
            saveError = nil
            rebuild()
            return true
        } catch {
            saveError = "Couldn't save inbox-summary.md: \(error.localizedDescription)"
            return false
        }
    }

    func dismissConflicts() { conflicts.removeAll() }

    // MARK: Claude actions

    /// Runs /summary in a conversation.
    func refresh() {
        save()
        conversations.send("/summary", title: "Summary")
    }

    /// Asks Claude to carry out the ticks and notes in the file. Claude still shows an
    /// approval table and waits for a yes before changing anything.
    func applyNotes() {
        guard save() else { return }
        conversations.send("I updated inbox-summary.md", title: "Apply summary notes")
    }
}
