import CCEmailCore
import Foundation
import Observation

/// User preferences, stored in UserDefaults.
@Observable @MainActor
final class AppSettings {
    private let defaults = UserDefaults.standard

    /// The cc-email workspace. Empty means "find it automatically".
    var repoPath: String { didSet { defaults.set(repoPath, forKey: "repoPath") } }
    /// Path to `claude`. Empty means "find it automatically".
    var claudePath: String { didSet { defaults.set(claudePath, forKey: "claudePath") } }
    /// `--model` for new processes, e.g. "opus[1m]". Running sessions switch with `set_model`.
    var model: String { didSet { defaults.set(model, forKey: "model") } }
    /// Show replies word by word as they arrive.
    var streamReplies: Bool { didSet { defaults.set(streamReplies, forKey: "streamReplies") } }

    init() {
        repoPath = defaults.string(forKey: "repoPath") ?? ""
        claudePath = defaults.string(forKey: "claudePath") ?? ""
        let storedModel = defaults.string(forKey: "model") ?? ""
        model = storedModel.isEmpty ? ModelCatalog.defaultModel : storedModel
        streamReplies = defaults.object(forKey: "streamReplies") as? Bool ?? true
    }
}
