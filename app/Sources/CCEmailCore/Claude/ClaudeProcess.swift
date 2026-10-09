import Foundation

/// What a running `claude` process produces: decoded stdout events, then one exit.
public enum ProcessOutput: Sendable {
    case event(StreamEvent)
    case exited(status: Int32, stderrTail: String)
}

/// A long-running `claude -p --input-format stream-json` process for one conversation.
/// Stdout is decoded into `output`; messages go in with `send(_:)`.
public final class ClaudeProcess: @unchecked Sendable {
    public let config: LaunchConfig
    public let output: AsyncStream<ProcessOutput>

    private let continuation: AsyncStream<ProcessOutput>.Continuation
    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    private let stderr = Pipe()
    /// Serializes stdin writes and all mutable state below.
    private let queue = DispatchQueue(label: "ccemail.claude-process")
    private var decoder = StreamDecoder()
    private var stderrTail = Data()
    private var stdinClosed = false
    private let requestCounter = NSLock()
    private var nextRequestNumber = 0
    private static let stderrTailLimit = 8 * 1024

    /// Writing to a pipe whose reader has exited raises SIGPIPE, which would kill the app.
    /// Ignoring it turns that into a write error instead.
    private static let ignoreSIGPIPE: Void = { signal(SIGPIPE, SIG_IGN) }()

    public init(config: LaunchConfig) {
        self.config = config
        (output, continuation) = AsyncStream.makeStream(of: ProcessOutput.self)
    }

    public var isRunning: Bool { process.isRunning }

    public func start() throws {
        _ = Self.ignoreSIGPIPE
        process.executableURL = URL(fileURLWithPath: config.claudePath)
        process.arguments = config.arguments
        process.environment = config.environment()
        process.currentDirectoryURL = config.workingDirectory
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            self.queue.async { self.handleStdout(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            self.queue.async { self.handleStderr(data) }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            guard let self else { return }
            self.queue.async { self.handleExit(status: status) }
        }
        try process.run()
    }

    /// Writes one message as a line of JSON.
    public func send(_ message: JSONValue) {
        let line = message.serialized() + "\n"
        queue.async { [self] in
            guard !stdinClosed, process.isRunning else { return }
            do {
                try stdin.fileHandleForWriting.write(contentsOf: Data(line.utf8))
            } catch {
                stdinClosed = true
            }
        }
    }

    /// A fresh ID for a control request the app sends.
    public func makeRequestId() -> String {
        requestCounter.lock()
        defer { requestCounter.unlock() }
        nextRequestNumber += 1
        return "ccemail-\(nextRequestNumber)"
    }

    /// Asks claude to stop the current turn. The process keeps running.
    public func interrupt() {
        send(Outbound.interrupt(requestId: makeRequestId()))
    }

    /// Ends the process: closes stdin, then SIGTERM, then SIGKILL if it hasn't exited.
    public func terminate(grace: TimeInterval = 2) {
        queue.async { [self] in
            if !stdinClosed {
                stdinClosed = true
                try? stdin.fileHandleForWriting.close()
            }
        }
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + grace) { [weak self] in
            if self?.process.isRunning == true { kill(pid, SIGKILL) }
        }
    }

    // MARK: Private, on `queue`

    private func handleStdout(_ data: Data) {
        if data.isEmpty {
            stdout.fileHandleForReading.readabilityHandler = nil
            return
        }
        for event in decoder.feed(data) {
            continuation.yield(.event(event))
        }
    }

    private func handleStderr(_ data: Data) {
        if data.isEmpty {
            stderr.fileHandleForReading.readabilityHandler = nil
            return
        }
        stderrTail.append(data)
        if stderrTail.count > Self.stderrTailLimit {
            stderrTail.removeFirst(stderrTail.count - Self.stderrTailLimit)
        }
    }

    private func handleExit(status: Int32) {
        // Pick up anything still in the pipes before reporting the exit.
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        if let rest = try? stdout.fileHandleForReading.readToEnd(), !rest.isEmpty {
            for event in decoder.feed(rest) { continuation.yield(.event(event)) }
        }
        for event in decoder.finish() { continuation.yield(.event(event)) }
        if let rest = try? stderr.fileHandleForReading.readToEnd() { stderrTail.append(rest) }
        stdinClosed = true
        continuation.yield(.exited(status: status, stderrTail: String(decoding: stderrTail, as: UTF8.self)))
        continuation.finish()
    }
}
