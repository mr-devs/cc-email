import CryptoKit
import Foundation

public enum FileIO {
    /// Writes via a temporary file in the same directory and a rename, so a reader
    /// (Claude, VS Code, the app's own watcher) never sees a half-written file.
    public static func writeAtomically(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    public static func read(_ url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    public static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
