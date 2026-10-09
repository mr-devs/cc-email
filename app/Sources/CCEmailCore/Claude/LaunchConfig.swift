import Foundation

/// The command line and environment for one `claude` conversation process.
public struct LaunchConfig: Sendable, Equatable {
    public var claudePath: String
    public var workingDirectory: URL
    public var sessionId: String
    /// True to continue an existing session (`--resume`), false to start one (`--session-id`).
    public var resume: Bool
    public var model: String?
    public var appendSystemPrompt: String?
    public var allowedTools: [String]
    public var includePartialMessages: Bool
    /// Added after everything else, e.g. `--strict-mcp-config` for the usage probe.
    public var extraArguments: [String] = []
    /// PATH for the child. Apps launched from Finder get a minimal PATH, so this comes from the login shell.
    public var path: String?

    public init(
        claudePath: String,
        workingDirectory: URL,
        sessionId: String,
        resume: Bool,
        model: String? = nil,
        appendSystemPrompt: String? = LaunchConfig.appPrompt,
        allowedTools: [String] = LaunchConfig.defaultAllowedTools,
        includePartialMessages: Bool = true,
        path: String? = nil
    ) {
        self.claudePath = claudePath
        self.workingDirectory = workingDirectory
        self.sessionId = sessionId
        self.resume = resume
        self.model = model
        self.appendSystemPrompt = appendSystemPrompt
        self.allowedTools = allowedTools
        self.includePartialMessages = includePartialMessages
        self.path = path
    }

    /// The two files the app also edits. Claude rewrites them as part of /summary and /draft-email,
    /// and a permission sheet for every one of those writes would be noise.
    public static let defaultAllowedTools = [
        "Edit(inbox-summary.md)",
        "Write(inbox-summary.md)",
        "Edit(drafts/**)",
        "Write(drafts/**)",
    ]

    public static let appPrompt = """
        You are running behind CC Email, a native Mac front end for this workspace. \
        The user reads your replies in a chat pane that renders Markdown, including tables, \
        and edits inbox-summary.md and drafts/*.md in the app's own views. \
        Tool permission prompts and AskUserQuestion are shown to the user as native dialogs. \
        Everything in CLAUDE.md still applies, including asking for an explicit yes in chat \
        before changing the mailbox.
        """

    public var arguments: [String] {
        var args = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--permission-prompt-tool", "stdio",
        ]
        if resume {
            args += ["--resume", sessionId]
        } else if !sessionId.isEmpty {
            args += ["--session-id", sessionId]
        }
        if includePartialMessages { args.append("--include-partial-messages") }
        if let model, !model.isEmpty { args += ["--model", model] }
        if let appendSystemPrompt, !appendSystemPrompt.isEmpty {
            args += ["--append-system-prompt", appendSystemPrompt]
        }
        if !allowedTools.isEmpty { args += ["--allowedTools", allowedTools.joined(separator: ",")] }
        return args + extraArguments
    }

    public func environment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        if let path { env["PATH"] = path }
        // Set when the app itself is started from inside Claude Code; the child shouldn't think it's nested.
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        // The app must only ever use the user's Claude Code login. With any of these set, claude
        // would bill an API key or another provider instead, so they never reach the child.
        for key in Self.nonSubscriptionAuthVariables { env.removeValue(forKey: key) }
        return env
    }

    public static let nonSubscriptionAuthVariables = [
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_BASE_URL",
        "CLAUDE_CODE_USE_BEDROCK",
        "CLAUDE_CODE_USE_VERTEX",
        "CLAUDE_CODE_USE_FOUNDRY",
    ]
}
