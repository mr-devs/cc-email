import AppKit
import Foundation

/// Development aids, all off unless an environment variable is set. Pair them with
/// `scripts/fake-claude.py` to check layouts without using any Claude Code usage.
///
/// - `CCEMAIL_DATA_DIR=/tmp/dir`: keep conversations there instead of Application Support.
/// - `CCEMAIL_WINDOW_SIZE=1410x686`: resize the main window at launch.
/// - `CCEMAIL_AUTORUN=/summary`: send this message once the startup check passes.
/// - `CCEMAIL_SNAPSHOT=/tmp/shot.png` with `CCEMAIL_SNAPSHOT_TIMES=3,8`: render the window to
///   `/tmp/shot-3.png`, `/tmp/shot-8.png`, … (no screen-recording permission needed), each with
///   a `.txt` of window and content sizes.
@MainActor
enum DevHooks {
    private static let env = ProcessInfo.processInfo.environment

    static func applicationDidLaunch() {
        if let size = env["CCEMAIL_WINDOW_SIZE"] {
            let parts = size.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    mainWindow?.setContentSize(NSSize(width: parts[0], height: parts[1]))
                }
            }
        }
        guard let path = env["CCEMAIL_SNAPSHOT"], !path.isEmpty else { return }
        let times = (env["CCEMAIL_SNAPSHOT_TIMES"] ?? "5").split(separator: ",").compactMap { Double($0) }
        for time in times {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) {
                let base = (path as NSString).deletingPathExtension
                snapshot(to: times.count == 1 ? path : "\(base)-\(Int(time)).png")
            }
        }
    }

    static func checkFinished(_ app: AppState) {
        guard let message = env["CCEMAIL_AUTORUN"], !message.isEmpty, app.launchContext != nil else { return }
        app.conversations.send(message, title: "Autorun")
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.sheetParent == nil && $0.contentView != nil && $0.frame.height > 200 }
    }

    private static func snapshot(to path: String) {
        guard let window = mainWindow, let content = window.contentView else { return }
        let view = content.superview ?? content
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        let report = """
            window content size: \(content.frame.size)
            window contentMinSize: \(window.contentMinSize)
            content fittingSize: \(content.fittingSize)
            split view widths: \(splitWidths(in: content))

            \(tree(view, depth: 0))
            """
        try? report.write(toFile: (path as NSString).deletingPathExtension + ".txt", atomically: true, encoding: .utf8)
    }

    /// The view hierarchy with frames, to spot a view larger than its window.
    private static func tree(_ view: NSView, depth: Int) -> String {
        guard depth < 14 else { return "" }
        let name = String(describing: type(of: view)).prefix(60)
        var fitting = ""
        if view.fittingSize != .zero { fitting = " fitting=\(view.fittingSize)" }
        var line = String(repeating: "  ", count: depth) + "\(name) \(view.frame)\(fitting)\n"
        for sub in view.subviews { line += tree(sub, depth: depth + 1) }
        return line
    }

    /// Widths of the panes in the outermost split view, to spot a column growing.
    private static func splitWidths(in view: NSView) -> [Int] {
        if let split = view as? NSSplitView { return split.arrangedSubviews.map { Int($0.frame.width) } }
        for sub in view.subviews {
            let widths = splitWidths(in: sub)
            if !widths.isEmpty { return widths }
        }
        return []
    }
}
