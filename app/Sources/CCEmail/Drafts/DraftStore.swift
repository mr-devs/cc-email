import CCEmailCore
import Foundation
import Observation

struct DraftEntry: Identifiable, Equatable {
    var url: URL
    var file: DraftFile
    var modified: Date
    var id: String { url.lastPathComponent }
    var filename: String { url.lastPathComponent }
}

/// The open draft: the copy last read from disk (`base`) and the user's working copy.
@Observable @MainActor
final class DraftEditor {
    let url: URL
    private(set) var base: DraftFile
    var working: DraftFile
    private(set) var conflicts: [String] = []
    private(set) var deletedOnDisk = false
    private(set) var saveError: String?

    init(url: URL, file: DraftFile) {
        self.url = url
        base = file
        working = file
    }

    var filename: String { url.lastPathComponent }

    var isDirty: Bool {
        working.to != base.to || working.cc != base.cc || working.bcc != base.bcc
            || working.subject != base.subject || working.body != base.body
    }

    func save() -> Bool {
        do {
            let text = working.serialized()
            try FileIO.writeAtomically(text, to: url)
            base = DraftFile(text: text)
            working = base
            conflicts = []
            saveError = nil
            return true
        } catch {
            saveError = "Couldn't save: \(error.localizedDescription)"
            return false
        }
    }

    /// The file changed on disk, e.g. Claude synced it and wrote a new draft_id.
    func diskChanged(_ theirs: DraftFile?) {
        guard let theirs else {
            deletedOnDisk = true
            return
        }
        deletedOnDisk = false
        if isDirty {
            let (merged, newConflicts) = DraftFile.merge(base: base, mine: working, theirs: theirs)
            base = theirs
            working = merged
            conflicts = newConflicts
        } else {
            base = theirs
            working = theirs
        }
    }

    func takeTheirs() {
        working = base
        conflicts = []
    }

    func dismissConflicts() { conflicts = [] }
}

@Observable @MainActor
final class DraftStore {
    private(set) var drafts: [DraftEntry] = []
    var selectedFilename: String? {
        didSet { openSelected() }
    }
    private(set) var editor: DraftEditor?
    /// Drafts saved in the app since Claude last synced them to Gmail.
    private(set) var needsSync: Set<String> {
        didSet { UserDefaults.standard.set(Array(needsSync), forKey: "draftsNeedingSync") }
    }

    @ObservationIgnored private let conversations: ConversationStore
    @ObservationIgnored private var directory: URL?

    init(conversations: ConversationStore) {
        self.conversations = conversations
        needsSync = Set(UserDefaults.standard.stringArray(forKey: "draftsNeedingSync") ?? [])
    }

    func open(repo: URL) {
        directory = repo.appendingPathComponent("drafts", isDirectory: true)
        reload()
    }

    func filesChanged() { reload() }

    func reload() {
        guard let directory else { return }
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]))
            ?? []
        let old = Dictionary(uniqueKeysWithValues: drafts.map { ($0.filename, $0) })
        drafts = urls
            .filter { $0.pathExtension == "md" && $0.lastPathComponent != "README.md" }
            .compactMap { url -> DraftEntry? in
                guard let text = try? FileIO.read(url) else { return nil }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                return DraftEntry(url: url, file: DraftFile(text: text), modified: modified)
            }
            .sorted { $0.modified > $1.modified }

        // A new draft_id means Claude recreated the Gmail draft from the file: it's in sync.
        for entry in drafts where needsSync.contains(entry.filename) {
            if let previous = old[entry.filename], previous.file.draftId != entry.file.draftId {
                needsSync.remove(entry.filename)
            }
        }
        needsSync = needsSync.filter { name in drafts.contains { $0.filename == name } }

        if let editor {
            editor.diskChanged(drafts.first { $0.filename == editor.filename }?.file)
        }
        if selectedFilename == nil { selectedFilename = drafts.first?.filename }
    }

    private func openSelected() {
        guard let name = selectedFilename, let entry = drafts.first(where: { $0.filename == name }) else {
            editor = nil
            return
        }
        if editor?.filename == name { return }
        if let editor, editor.isDirty { _ = editor.save() }
        editor = DraftEditor(url: entry.url, file: entry.file)
    }

    // MARK: Actions

    func save() {
        guard let editor, editor.isDirty else { return }
        if editor.save() { needsSync.insert(editor.filename) }
    }

    /// Saves, then asks /draft-email to push the file to the Gmail draft.
    func sync() {
        guard let editor else { return }
        save()
        guard editor.saveError == nil else { return }
        conversations.send("I edited drafts/\(editor.filename). Sync it to the Gmail draft.", title: "Sync draft")
    }

    /// Asks Claude to send. Claude asks for a yes in chat, and the send itself raises a permission dialog.
    func send() {
        guard let editor else { return }
        save()
        guard editor.saveError == nil else { return }
        conversations.send("Send the draft in drafts/\(editor.filename).", title: "Send draft")
    }
}
