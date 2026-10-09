import CCEmailCore
import SwiftUI

struct DraftsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var store = app.drafts
        HSplitView {
            List(selection: $store.selectedFilename) {
                ForEach(store.drafts) { entry in
                    DraftRow(entry: entry, needsSync: store.needsSync.contains(entry.filename))
                        .tag(entry.filename)
                }
            }
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
            .overlay {
                if store.drafts.isEmpty {
                    ContentUnavailableView(
                        "No drafts", systemImage: "square.and.pencil",
                        description: Text("Drafts made with /draft-email appear here.")
                    )
                }
            }

            Group {
                if let editor = store.editor {
                    DraftEditorView(editor: editor).id(editor.filename)
                } else {
                    Text("Select a draft").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 380)
        }
        .navigationTitle("Drafts")
    }
}

private struct DraftRow: View {
    let entry: DraftEntry
    let needsSync: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if needsSync {
                    Circle().fill(.orange).frame(width: 7, height: 7).help("Edited since the last sync to Gmail")
                }
                Text(entry.file.subject.isEmpty ? "(no subject)" : entry.file.subject).lineLimit(1)
            }
            Text(entry.file.to.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(entry.modified, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private struct DraftEditorView: View {
    @Environment(AppState.self) private var app
    @Bindable var editor: DraftEditor

    var body: some View {
        VStack(spacing: 0) {
            if editor.deletedOnDisk {
                Banner(icon: "paperplane", text: "This draft's file is gone, which usually means it was sent.")
            }
            if let error = editor.saveError {
                Banner(icon: "exclamationmark.triangle", text: error, tint: .orange)
            }
            if !editor.conflicts.isEmpty {
                Banner(
                    icon: "exclamationmark.arrow.triangle.2.circlepath",
                    text: "The file changed while you were editing. Your version of \(editor.conflicts.joined(separator: ", ")) is kept.",
                    tint: .orange,
                    action: ("Use the File's Version", editor.takeTheirs)
                )
            }
            Form {
                RecipientField(title: "To", recipients: $editor.working.to)
                RecipientField(title: "Cc", recipients: $editor.working.cc)
                RecipientField(title: "Bcc", recipients: $editor.working.bcc)
                TextField("Subject", text: $editor.working.subject)
                LabeledContent("From", value: editor.working.from)
            }
            .formStyle(.columns)
            .padding(14)
            Divider()
            TextEditor(text: $editor.working.body)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
            Divider()
            HStack(spacing: 10) {
                Text("Plain text. Markdown is sent as typed.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                if let link = editor.working.gmailURL, let url = URL(string: link) {
                    Link("Open in Gmail", destination: url)
                }
                Button("Save") { app.drafts.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!editor.isDirty)
                Button("Sync to Gmail") { app.drafts.sync() }
                    .help("Save, then have /draft-email update the Gmail draft from this file")
                    .disabled(app.launchContext == nil || editor.deletedOnDisk)
                Button("Send…") { app.drafts.send() }
                    .help("Ask Claude to send it. Claude confirms in chat, and the send itself needs your permission.")
                    .disabled(app.launchContext == nil || editor.deletedOnDisk)
            }
            .padding(12)
        }
    }
}

/// A comma-separated recipients field. It keeps its own text while focused, so typing
/// "a@x.com, " isn't rewritten mid-word.
private struct RecipientField: View {
    let title: String
    @Binding var recipients: [String]
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text)
            .focused($focused)
            .onAppear { text = recipients.joined(separator: ", ") }
            .onChange(of: text) { _, value in
                if focused { recipients = DraftFile.recipients(from: value) }
            }
            .onChange(of: recipients) { _, value in
                if !focused { text = value.joined(separator: ", ") }
            }
    }
}
