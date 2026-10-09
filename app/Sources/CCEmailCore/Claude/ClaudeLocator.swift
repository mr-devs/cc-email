import Foundation

/// Finds the `claude` binary, the user's login-shell PATH, and the cc-email workspace.
public enum ClaudeLocator {
    public static let fallbackPath = [
        "\(NSHomeDirectory())/.local/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ].joined(separator: ":")

    /// PATH as the user's login shell sets it. Hooks and skills call tools like `remindctl`
    /// and `python3`, which a Finder-launched app wouldn't otherwise find.
    public static func loginShellPATH(timeout: TimeInterval = 3) -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let output = run(shell, ["-lc", "printf %s \"$PATH\""], timeout: timeout)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let output, !output.isEmpty else { return fallbackPath }
        return output
    }

    /// The first executable `claude` found: an explicit setting, then common install locations, then PATH.
    public static func findClaude(configured: String? = nil, path: String) -> String? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let configured, !configured.isEmpty {
            candidates.append((configured as NSString).expandingTildeInPath)
        }
        candidates += [
            "\(NSHomeDirectory())/.local/bin/claude",
            "\(NSHomeDirectory())/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        candidates += path.split(separator: ":").map { "\($0)/claude" }
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    /// `claude --version`, e.g. "2.1.295 (Claude Code)".
    public static func version(of claudePath: String) -> String? {
        run(claudePath, ["--version"], timeout: 10)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True if `url` looks like a cc-email workspace.
    public static func isWorkspace(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.appendingPathComponent("CLAUDE.md").path)
            && fm.fileExists(atPath: url.appendingPathComponent(".claude/skills/summary/SKILL.md").path)
    }

    /// Walks up from `start` (e.g. the app bundle inside `app/build/`) looking for the workspace.
    public static func findWorkspace(from start: URL) -> URL? {
        var url = start.standardizedFileURL
        while url.path != "/" {
            if isWorkspace(url) { return url }
            url.deleteLastPathComponent()
        }
        return nil
    }

    /// How `claude` would authenticate if started with `config`'s environment and working directory.
    /// Runs `claude auth status`, which makes no model call. Nil if it can't be read.
    public static func authStatus(for config: LaunchConfig) -> AuthStatus? {
        guard let output = run(
            config.claudePath, ["auth", "status", "--json"], timeout: 15,
            environment: config.environment(), workingDirectory: config.workingDirectory
        ), let json = try? JSONValue.parse(output) else { return nil }
        return AuthStatus(json: json)
    }

    private final class OutputBox: @unchecked Sendable {
        var data: Data?
    }

    /// Runs a short command and returns its stdout, or nil on failure or timeout.
    static func run(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return nil }

        // Drain stdout on another thread so a full pipe can't block the child,
        // and so a hung child can't block us past the timeout.
        let output = OutputBox()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            output.data = stdout.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        // A background grandchild can hold the pipe open after the child exits; give up after a second.
        guard drained.wait(timeout: .now() + 1) == .success,
              process.terminationStatus == 0, let data = output.data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

/// The parts of `claude auth status --json` the app checks. Account details are deliberately not kept.
public struct AuthStatus: Sendable, Equatable {
    public var loggedIn: Bool
    public var authMethod: String
    public var subscriptionType: String?

    public init(loggedIn: Bool, authMethod: String, subscriptionType: String?) {
        self.loggedIn = loggedIn
        self.authMethod = authMethod
        self.subscriptionType = subscriptionType
    }

    public init(json: JSONValue) {
        loggedIn = json["loggedIn"]?.boolValue ?? false
        authMethod = json["authMethod"]?.stringValue ?? "unknown"
        subscriptionType = json["subscriptionType"]?.stringValue
    }

    /// The app only runs on the user's Claude Code (claude.ai) login, never an API key.
    public var usesClaudeCodeLogin: Bool { loggedIn && authMethod == "claude.ai" }
}
