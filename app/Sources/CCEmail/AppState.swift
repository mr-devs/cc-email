import AppKit
import CCEmailCore
import Foundation
import Observation

/// What a conversation needs to start a `claude` process.
struct LaunchContext {
    var claudePath: String
    var repoURL: URL
    var path: String
    var model: String?
    var streamReplies: Bool
}

/// Result of checking that the workspace and Claude Code are usable.
struct EnvironmentCheck {
    var repoURL: URL?
    var claudePath: String?
    var claudeVersion: String?
    var auth: AuthStatus?
    var path: String = ClaudeLocator.fallbackPath
    var checking = true

    /// Why the app can't run conversations, or nil if it can.
    var problem: String? {
        if checking { return nil }
        if repoURL == nil { return "Choose your cc-email folder to get started." }
        if claudePath == nil { return "Couldn't find the claude command. Set its path in Settings." }
        guard let auth else { return "Couldn't read Claude Code's login status (claude auth status)." }
        if !auth.loggedIn { return "Claude Code isn't signed in. Run `claude auth login` in Terminal." }
        if !auth.usesClaudeCodeLogin {
            return "Claude Code would use \(auth.authMethod) instead of your Claude Code login, so the app won't start it."
        }
        return nil
    }
}

@Observable @MainActor
final class AppState {
    let settings = AppSettings()
    let usage = UsageStore()
    var check = EnvironmentCheck()
    var labelNames = LabelNames()
    private(set) var conversations: ConversationStore!
    private(set) var summary: SummaryStore!
    private(set) var drafts: DraftStore!
    private var watcher: FileWatcher?

    init() {
        conversations = ConversationStore(contextProvider: { [unowned self] in self.launchContext })
        conversations.labelNames = { [unowned self] in self.labelNames }
        conversations.onPlanUsage = { [unowned self] in self.usage.update($0) }
        conversations.onModels = { [unowned self] in self.usage.update($0) }
        summary = SummaryStore(conversations: conversations)
        drafts = DraftStore(conversations: conversations)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.conversations.shutdownAll() }
        }
    }

    var launchContext: LaunchContext? {
        guard check.problem == nil, !check.checking,
              let claudePath = check.claudePath, let repoURL = check.repoURL else { return nil }
        let model = settings.model.trimmingCharacters(in: .whitespaces)
        return LaunchContext(
            claudePath: claudePath, repoURL: repoURL, path: check.path,
            model: model.isEmpty ? nil : model, streamReplies: settings.streamReplies
        )
    }

    /// Finds the workspace and claude, and checks which login claude would use.
    /// Runs `claude --version` and `claude auth status`; neither makes a model call.
    func runCheck() async {
        check.checking = true
        let configuredRepo = settings.repoPath
        let configuredClaude = settings.claudePath
        let result = await Task.detached(priority: .userInitiated) { () -> EnvironmentCheck in
            var c = EnvironmentCheck()
            c.path = ClaudeLocator.loginShellPATH()
            if !configuredRepo.isEmpty {
                let url = URL(fileURLWithPath: (configuredRepo as NSString).expandingTildeInPath)
                c.repoURL = ClaudeLocator.isWorkspace(url) ? url : nil
            } else {
                c.repoURL = ClaudeLocator.findWorkspace(from: Bundle.main.bundleURL)
                    ?? ClaudeLocator.findWorkspace(from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            }
            c.claudePath = ClaudeLocator.findClaude(configured: configuredClaude, path: c.path)
            if let claude = c.claudePath {
                c.claudeVersion = ClaudeLocator.version(of: claude)
                let probe = LaunchConfig(
                    claudePath: claude,
                    workingDirectory: c.repoURL ?? URL(fileURLWithPath: NSHomeDirectory()),
                    sessionId: "", resume: false, path: c.path
                )
                c.auth = ClaudeLocator.authStatus(for: probe)
            }
            c.checking = false
            return c
        }.value
        check = result
        if let repo = result.repoURL {
            if settings.repoPath.isEmpty { settings.repoPath = repo.path }
            openWorkspace(repo)
        }
        if launchContext != nil {
            refreshUsage()
            usage.startTimer(context: { [weak self] in self?.launchContext }, conversations: conversations)
        }
    }

    /// Plan and context usage from Claude Code (control requests only, no model call).
    func refreshUsage() {
        usage.refresh(context: launchContext, conversations: conversations)
    }

    /// Sets the model for new sessions and switches running ones.
    func setModel(_ model: String) {
        guard model != settings.model else { return }
        settings.model = model
        conversations.applyModel(model)
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose your cc-email folder (the one with CLAUDE.md and .claude/skills)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.repoPath = url.path
        Task { await runCheck() }
    }

    private func openWorkspace(_ repo: URL) {
        loadLabelNames(repo)
        summary.open(repo: repo)
        drafts.open(repo: repo)
        watcher?.stop()
        let root = repo.resolvingSymlinksInPath().path
        watcher = FileWatcher(root: repo) { [weak self] paths in
            Task { @MainActor in self?.filesChanged(paths, root: root) }
        }
        watcher?.start()
    }

    private func loadLabelNames(_ repo: URL) {
        let text = (try? FileIO.read(repo.appendingPathComponent("CLAUDE.local.md"))) ?? ""
        labelNames = LabelNames(claudeLocalMarkdown: text)
    }

    private func filesChanged(_ paths: [String], root: String) {
        let relative = paths.map { path -> String in
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            return resolved.hasPrefix(root + "/") ? String(resolved.dropFirst(root.count + 1)) : resolved
        }
        if relative.contains("inbox-summary.md") { summary.fileChanged() }
        if relative.contains(where: { $0.hasPrefix("drafts/") }) { drafts.filesChanged() }
        if relative.contains("CLAUDE.local.md"), let repo = check.repoURL { loadLabelNames(repo) }
    }
}
