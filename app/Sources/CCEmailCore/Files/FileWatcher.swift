import CoreServices
import Foundation

/// Watches a directory tree with FSEvents and reports changed file paths.
/// FSEvents follows renames and replacements, which matters because editors and
/// Claude's Write tool replace files rather than editing them in place.
public final class FileWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable ([String]) -> Void

    private let root: URL
    private let handler: Handler
    private let queue = DispatchQueue(label: "ccemail.file-watcher")
    private var stream: FSEventStreamRef?

    public init(root: URL, handler: @escaping Handler) {
        self.root = root
        self.handler = handler
    }

    deinit { stop() }

    public func start(latency: TimeInterval = 0.3) {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let array = unsafeBitCast(paths, to: NSArray.self)
            let changed = (0..<count).compactMap { array[$0] as? String }
            watcher.handler(changed)
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
