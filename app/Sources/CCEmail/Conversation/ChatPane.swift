import CCEmailCore
import SwiftUI

/// A conversation: transcript, composer, quick replies and skill shortcuts.
struct ChatPane: View {
    @Bindable var conversation: Conversation
    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            Divider()
            composer
            UsageFooter(conversation: conversation)
        }
        // A fixed ideal width: otherwise a long tool line or table raises the pane's ideal
        // width, and the inspector grows until the window's content overflows.
        .frame(minWidth: 320, idealWidth: 380, maxWidth: .infinity)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(conversation.title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            StatusBadge(conversation: conversation)
            Button("Clear", systemImage: "eraser") { conversation.store?.clear(conversation) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Start a fresh conversation; this one stays in the sidebar (⌘K)")
                .keyboardShortcut("k", modifiers: .command)
                .disabled(conversation.isBusy || conversation.items.isEmpty)
            if conversation.isBusy {
                Button("Stop", systemImage: "stop.fill") { conversation.stop() }
                    .labelStyle(.iconOnly)
                    .help("Stop this turn (⌘.)")
                    .keyboardShortcut(".", modifiers: .command)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if conversation.items.isEmpty {
                        EmptyChat()
                    }
                    ForEach(conversation.items) { item in
                        TranscriptRow(item: item).id(item.id)
                    }
                    if conversation.isBusy {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(conversation.state == .starting ? "Starting Claude Code…" : "Working…")
                                .foregroundStyle(.secondary)
                        }
                        .id("working")
                    }
                }
                .padding(12)
            }
            .onChange(of: conversation.items.last?.text) { scrollToEnd(proxy) }
            .onChange(of: conversation.items.count) { scrollToEnd(proxy) }
            .onAppear { scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if conversation.isBusy {
            proxy.scrollTo("working", anchor: .bottom)
        } else if let last = conversation.items.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button("Yes") { conversation.send("yes") }
                    .help("Approve what Claude proposed")
                Button("No") { conversation.send("no") }
                SkillsMenu { command, prefillOnly in
                    if prefillOnly {
                        draft = command
                        composerFocused = true
                    } else {
                        conversation.send(command)
                    }
                }
                Spacer()
            }
            .disabled(conversation.isBusy)
            .controlSize(.small)

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message Claude…  (Return to send, ⌥Return for a new line)", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused($composerFocused)
                    .onSubmit(submit)
                Button("Send", systemImage: "arrow.up.circle.fill", action: submit)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .buttonStyle(.borderless)
                    .disabled(conversation.isBusy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(8)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        }
        .padding(10)
    }

    private func submit() {
        guard !conversation.isBusy else { return }
        let text = draft
        draft = ""
        conversation.send(text)
    }
}

struct StatusBadge: View {
    let conversation: Conversation

    var body: some View {
        switch conversation.state {
        case .idle:
            EmptyView()
        case .starting, .running:
            ProgressView().controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("The last turn failed. Send another message to retry.")
        }
    }
}

/// Shortcuts for the workspace's skills.
struct SkillsMenu: View {
    /// (command, prefillOnly): prefill puts the text in the composer instead of sending it.
    let run: (String, Bool) -> Void

    var body: some View {
        Menu("Skills") {
            Button("Summarize inbox  /summary") { run("/summary", false) }
            Menu("Suggest replies") {
                Button("Urgent") { run("/suggest-replies urgent", false) }
                Button("Easy") { run("/suggest-replies easy", false) }
            }
            Button("File away  /file-away") { run("/file-away", false) }
            Button("Scholar digest  /scholar-digest") { run("/scholar-digest", false) }
            Divider()
            Button("Draft an email…  /draft-email") { run("/draft-email ", true) }
            Button("List contacts  /contacts list") { run("/contacts list", false) }
        }
        .fixedSize()
    }
}

private struct EmptyChat: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ask Claude about your mail, or pick a skill.")
                .foregroundStyle(.secondary)
            Text("Claude proposes every mailbox change and waits for your yes. Tool permissions and questions open as dialogs.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 20)
    }
}
