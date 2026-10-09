import CCEmailCore
import SwiftUI

enum SidebarItem: Hashable {
    case summary
    case drafts
    case conversation(UUID)
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var selection: SidebarItem? = .summary
    @State private var showChat = true

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                if let problem = app.check.problem {
                    SetupBanner(problem: problem)
                }
                detail
            }
        }
        .sheet(item: Binding(get: { app.conversations.nextPrompt }, set: { _ in })) { prompt in
            if prompt.request.isAskUserQuestion {
                QuestionSheet(conversation: prompt.conversation, request: prompt.request)
            } else {
                PermissionSheet(conversation: prompt.conversation, request: prompt.request, labels: app.labelNames)
            }
        }
        .task {
            await app.runCheck()
            DevHooks.checkFinished(app)
        }
        .onChange(of: selection) { _, value in
            if case .conversation(let id) = value,
               let conversation = app.conversations.conversations.first(where: { $0.id == id })
            {
                app.conversations.activate(conversation)
            }
        }
        .onChange(of: app.conversations.activeID) { _, _ in
            // A button elsewhere started a conversation: make sure it's visible.
            if case .conversation = selection {
                if let id = app.conversations.activeID { selection = .conversation(id) }
            } else {
                showChat = true
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Mail") {
                Label("Summary", systemImage: "tray.full").tag(SidebarItem.summary)
                Label("Drafts", systemImage: "square.and.pencil")
                    .badge(app.drafts.drafts.count)
                    .tag(SidebarItem.drafts)
            }
            Section("Conversations") {
                ForEach(app.conversations.sorted) { conversation in
                    ConversationRow(conversation: conversation)
                        .tag(SidebarItem.conversation(conversation.id))
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                if selection == .conversation(conversation.id) { selection = .summary }
                                app.conversations.delete(conversation)
                            }
                        }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .toolbar {
            ToolbarItem {
                Button("New Conversation", systemImage: "plus.bubble") {
                    let conversation = app.conversations.newConversation()
                    selection = .conversation(conversation.id)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .conversation(let id):
            if let conversation = app.conversations.conversations.first(where: { $0.id == id }) {
                ChatPane(conversation: conversation)
            } else {
                Text("Select a conversation").foregroundStyle(.secondary)
            }
        case .drafts:
            DraftsView().modifier(ChatInspector(isPresented: $showChat))
        default:
            SummaryView().modifier(ChatInspector(isPresented: $showChat))
        }
    }
}

/// The active conversation beside the Summary and Drafts views.
private struct ChatInspector: ViewModifier {
    @Environment(AppState.self) private var app
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .inspector(isPresented: $isPresented) {
                Group {
                    if let conversation = app.conversations.active {
                        ChatPane(conversation: conversation)
                    } else {
                        VStack(spacing: 0) {
                            ContentUnavailableView {
                                Label("No conversation", systemImage: "bubble.left.and.bubble.right")
                            } actions: {
                                Button("New Conversation") { app.conversations.newConversation() }
                            }
                            Divider()
                            UsageFooter(conversation: nil).padding(.top, 8)
                        }
                    }
                }
                .inspectorColumnWidth(min: 320, ideal: 380, max: 640)
            }
            .toolbar {
                ToolbarItem {
                    Button("Chat", systemImage: "sidebar.right") { isPresented.toggle() }
                        .help("Show or hide the conversation")
                }
            }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(conversation.title).lineLimit(1)
                Text(conversation.updatedAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !conversation.pendingPermissions.isEmpty {
                Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            } else {
                StatusBadge(conversation: conversation)
            }
        }
    }
}

private struct SetupBanner: View {
    @Environment(AppState.self) private var app
    @Environment(\.openSettings) private var openSettings
    let problem: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(problem).font(.callout).lineLimit(3)
            Spacer(minLength: 0)
            if app.check.repoURL == nil {
                Button("Choose Folder…") { app.chooseWorkspace() }
            }
            Button("Settings…") { openSettings() }
            Button("Check Again") { Task { await app.runCheck() } }
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.1))
    }
}
