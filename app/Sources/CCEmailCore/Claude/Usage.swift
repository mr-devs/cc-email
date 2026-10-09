import Foundation

/// Plan limits from Claude Code's `get_usage` control request (the same numbers as `/usage`).
/// Claude Code fetches them with its own login; the app never touches credentials.
/// The request is marked experimental upstream, so every field is optional.
public struct PlanUsage: Sendable, Equatable, Codable {
    public struct Window: Sendable, Equatable, Codable {
        /// 0–100.
        public var percent: Double
        public var resetsAt: Date?
    }

    public var session: Window?
    public var weekly: Window?
    public var subscriptionType: String?
    public var fetchedAt: Date

    public init(session: Window?, weekly: Window?, subscriptionType: String?, fetchedAt: Date) {
        self.session = session
        self.weekly = weekly
        self.subscriptionType = subscriptionType
        self.fetchedAt = fetchedAt
    }

    /// Nil when plan limits don't apply or the response isn't recognised.
    public init?(response: JSONValue, now: Date = Date()) {
        guard response["rate_limits_available"]?.boolValue != false,
              let limits = response["rate_limits"], limits.objectValue != nil else { return nil }
        func window(_ key: String) -> Window? {
            guard let w = limits[key], let percent = w["utilization"]?.doubleValue else { return nil }
            return Window(percent: percent, resetsAt: w["resets_at"]?.stringValue.flatMap(Self.parseDate))
        }
        session = window("five_hour")
        weekly = window("seven_day")
        guard session != nil || weekly != nil else { return nil }
        subscriptionType = response["subscription_type"]?.stringValue
        fetchedAt = now
    }

    /// ISO 8601 with optional fractional seconds of any length, e.g. "2026-10-09T06:40:00.475604+00:00".
    static func parseDate(_ text: String) -> Date? {
        let trimmed = text.replacing(/\.\d+/, with: "")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }
}

/// How full a session's context window is, from `get_context_usage`.
public struct ContextUsage: Sendable, Equatable {
    public var percentage: Double
    public var totalTokens: Int
    public var maxTokens: Int
    public var model: String?

    public init?(response: JSONValue) {
        guard let total = response["totalTokens"]?.intValue, let max = response["maxTokens"]?.intValue, max > 0 else {
            return nil
        }
        totalTokens = total
        maxTokens = max
        percentage = response["percentage"]?.doubleValue ?? Double(total) / Double(max) * 100
        model = response["model"]?.stringValue
    }
}

/// A model the user can pick, from `list_models` or the built-in fallback.
public struct ModelOption: Sendable, Equatable, Codable, Identifiable, Hashable {
    /// What's passed to `--model` and `set_model`, e.g. "opus[1m]" or "sonnet".
    public var value: String
    public var displayName: String
    public var id: String { value }

    public init(value: String, displayName: String) {
        self.value = value
        self.displayName = displayName
    }
}

public enum ModelCatalog {
    /// Opus 5.5 with the 1M-token context window.
    public static let defaultModel = "opus[1m]"

    /// Used until Claude Code has listed the account's models.
    public static let fallback = [
        ModelOption(value: "opus[1m]", displayName: "Opus 5.5 (1M context)"),
        ModelOption(value: "opus", displayName: "Opus 5.5"),
        ModelOption(value: "sonnet", displayName: "Sonnet 5.5"),
        ModelOption(value: "haiku", displayName: "Haiku 5.5"),
        ModelOption(value: "fable", displayName: "Fable 5.1"),
    ]

    /// Options from a `list_models` response, with the 1M-context Opus first. Claude Code's
    /// "default" entry is left out: the app always passes an explicit model.
    public static func options(fromListModels response: JSONValue) -> [ModelOption] {
        let listed = (response["models"]?.arrayValue ?? []).compactMap { m -> ModelOption? in
            guard let value = m["value"]?.stringValue, value != "default",
                  let name = m["displayName"]?.stringValue else { return nil }
            return ModelOption(value: value, displayName: name)
        }
        guard !listed.isEmpty else { return fallback }
        var options = listed
        if let opus = listed.first(where: { $0.value == "opus" }) {
            options.insert(ModelOption(value: "opus[1m]", displayName: "\(opus.displayName) (1M context)"), at: 0)
        }
        return options
    }

    /// A readable name for a model value, e.g. "opus[1m]" → "Opus 5.5 (1M context)".
    public static func displayName(for value: String, in options: [ModelOption]) -> String {
        options.first { $0.value == value }?.displayName
            ?? fallback.first { $0.value == value }?.displayName
            ?? value
    }
}
