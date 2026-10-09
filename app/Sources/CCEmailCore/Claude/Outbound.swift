import Foundation

/// Messages the app writes to claude's stdin (`--input-format stream-json`), one per line.
/// The shapes follow the Claude Agent SDK, which drives the CLI the same way.
public enum Outbound {
    public static func userMessage(_ text: String, sessionId: String) -> JSONValue {
        [
            "type": "user",
            "message": ["role": "user", "content": .string(text)],
            "parent_tool_use_id": nil,
            "session_id": .string(sessionId),
        ]
    }

    public static func initialize(requestId: String) -> JSONValue {
        controlRequest(requestId: requestId, ["subtype": "initialize"])
    }

    public static func interrupt(requestId: String) -> JSONValue {
        controlRequest(requestId: requestId, ["subtype": "interrupt", "cancel_queued": true])
    }

    /// Plan limits, as shown by `/usage`. No model call.
    public static func getUsage(requestId: String) -> JSONValue {
        controlRequest(requestId: requestId, ["subtype": "get_usage"])
    }

    /// How full the session's context window is. No model call.
    public static func getContextUsage(requestId: String) -> JSONValue {
        controlRequest(requestId: requestId, ["subtype": "get_context_usage"])
    }

    /// The models the account can use. No model call.
    public static func listModels(requestId: String) -> JSONValue {
        controlRequest(requestId: requestId, ["subtype": "list_models"])
    }

    /// Switches the running session's model from the next turn on.
    public static func setModel(_ model: String, requestId: String) -> JSONValue {
        controlRequest(requestId: requestId, ["subtype": "set_model", "model": .string(model)])
    }

    /// Allows a tool call. `updatedInput` is required by the CLI, so pass the original
    /// input unless it was changed (AskUserQuestion adds its `answers` here).
    public static func allow(
        requestId: String,
        toolUseId: String?,
        updatedInput: JSONValue,
        updatedPermissions: [JSONValue] = []
    ) -> JSONValue {
        var result: [String: JSONValue] = ["behavior": "allow", "updatedInput": updatedInput]
        if !updatedPermissions.isEmpty { result["updatedPermissions"] = .array(updatedPermissions) }
        if let toolUseId { result["toolUseID"] = .string(toolUseId) }
        return controlSuccess(requestId: requestId, .object(result))
    }

    public static func deny(requestId: String, toolUseId: String?, message: String) -> JSONValue {
        var result: [String: JSONValue] = ["behavior": "deny", "message": .string(message)]
        if let toolUseId { result["toolUseID"] = .string(toolUseId) }
        return controlSuccess(requestId: requestId, .object(result))
    }

    /// Answers a control request the app doesn't support, so the CLI doesn't wait on it.
    public static func controlError(requestId: String, message: String) -> JSONValue {
        [
            "type": "control_response",
            "response": ["subtype": "error", "request_id": .string(requestId), "error": .string(message)],
        ]
    }

    /// AskUserQuestion's input with the user's answers added, keyed by question text.
    /// Multi-select answers are joined with ", ".
    public static func answeredQuestions(input: JSONValue, answers: [String: String]) -> JSONValue {
        var dict = input.objectValue ?? [:]
        dict["answers"] = .object(answers.mapValues { .string($0) })
        return .object(dict)
    }

    private static func controlRequest(requestId: String, _ request: JSONValue) -> JSONValue {
        ["type": "control_request", "request_id": .string(requestId), "request": request]
    }

    private static func controlSuccess(requestId: String, _ response: JSONValue) -> JSONValue {
        [
            "type": "control_response",
            "response": ["subtype": "success", "request_id": .string(requestId), "response": response],
        ]
    }
}
