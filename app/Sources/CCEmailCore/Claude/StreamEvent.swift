import Foundation

/// One line of `claude --output-format stream-json`, decoded into the parts the app uses.
/// Anything unrecognised is kept as `.other` so new CLI versions don't break the app.
public enum StreamEvent: Sendable, Equatable {
    case initialized(SessionInfo)
    case assistant(AssistantMessage)
    case toolResults([ToolResult], parentToolUseId: String?)
    case textDelta(String, parentToolUseId: String?)
    case result(TurnResult)
    case permissionRequest(PermissionRequest)
    /// A control request the app doesn't handle. It must still be answered, or the CLI waits forever.
    case unsupportedControlRequest(requestId: String, subtype: String)
    case controlCancel(requestId: String)
    case controlResponse(requestId: String, success: Bool, payload: JSONValue?, error: String?)
    case permissionDenied(toolName: String, message: String)
    case other(JSONValue)
    /// A stdout line that isn't JSON.
    case unparsable(String)
}

public struct SessionInfo: Sendable, Equatable {
    public var sessionId: String
    public var model: String
    public var cwd: String
    public var claudeCodeVersion: String
    public var permissionMode: String
    /// Where claude got its credentials. "none" or "oauth" means the user's Claude Code login.
    public var apiKeySource: String
    public var mcpServers: [MCPServerStatus]
    public var slashCommands: [String]
    public var tools: [String]

    /// True when the session runs on the user's Claude Code login rather than an API key.
    public var usesClaudeCodeLogin: Bool { ["none", "oauth"].contains(apiKeySource) }
}

public struct MCPServerStatus: Sendable, Equatable {
    public var name: String
    public var status: String
}

public struct AssistantMessage: Sendable, Equatable {
    /// The API message ID. One API message can arrive as several events, one per content block.
    public var messageId: String?
    public var parentToolUseId: String?
    public var blocks: [ContentBlock]
    public var error: String?
}

public enum ContentBlock: Sendable, Equatable {
    case text(String)
    case thinking(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case other(type: String)
}

public struct ToolResult: Sendable, Equatable {
    public var toolUseId: String
    public var isError: Bool
    public var text: String
}

public struct TurnResult: Sendable, Equatable {
    public var subtype: String
    public var isError: Bool
    public var sessionId: String?
    public var resultText: String?
    public var durationMs: Int?
    public var numTurns: Int?
    public var totalCostUSD: Double?
    public var permissionDenials: [PermissionDenial]
    public var errors: [String]
}

public struct PermissionDenial: Sendable, Equatable {
    public var toolName: String
    public var toolUseId: String?
    public var toolInput: JSONValue?
}

public struct PermissionRequest: Sendable, Equatable, Identifiable {
    public var id: String { requestId }
    public var requestId: String
    public var toolName: String
    public var input: JSONValue
    public var toolUseId: String?
    public var title: String?
    public var displayName: String?
    public var description: String?
    public var decisionReason: String?
    public var blockedPath: String?
    public var agentId: String?
    /// Rules the CLI suggests for "always allow", in `PermissionUpdate` form. Sent back as-is.
    public var suggestions: [JSONValue]
    public var suppressAlwaysAllow: Bool

    public var isAskUserQuestion: Bool { toolName == "AskUserQuestion" }
}

// MARK: - Decoding

extension StreamEvent {
    public static func decode(line: String) -> StreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard let json = try? JSONValue.parse(trimmed), json.objectValue != nil else {
            return .unparsable(trimmed)
        }
        return decode(json)
    }

    public static func decode(_ json: JSONValue) -> StreamEvent {
        switch json["type"]?.stringValue {
        case "system":
            return decodeSystem(json)
        case "assistant":
            return decodeAssistant(json)
        case "user":
            return decodeUser(json)
        case "stream_event":
            return decodeStreamEvent(json)
        case "result":
            return .result(decodeResult(json))
        case "control_request":
            return decodeControlRequest(json)
        case "control_cancel_request":
            if let id = json["request_id"]?.stringValue { return .controlCancel(requestId: id) }
        case "control_response":
            if let response = json["response"], let id = response["request_id"]?.stringValue {
                return .controlResponse(
                    requestId: id,
                    success: response["subtype"]?.stringValue == "success",
                    payload: response["response"],
                    error: response["error"]?.stringValue
                )
            }
        default:
            break
        }
        return .other(json)
    }

    private static func decodeSystem(_ json: JSONValue) -> StreamEvent {
        switch json["subtype"]?.stringValue {
        case "init":
            let servers = (json["mcp_servers"]?.arrayValue ?? []).compactMap { s -> MCPServerStatus? in
                guard let name = s["name"]?.stringValue else { return nil }
                return MCPServerStatus(name: name, status: s["status"]?.stringValue ?? "unknown")
            }
            return .initialized(SessionInfo(
                sessionId: json["session_id"]?.stringValue ?? "",
                model: json["model"]?.stringValue ?? "",
                cwd: json["cwd"]?.stringValue ?? "",
                claudeCodeVersion: json["claude_code_version"]?.stringValue ?? "",
                permissionMode: json["permissionMode"]?.stringValue ?? "",
                apiKeySource: json["apiKeySource"]?.stringValue ?? "unknown",
                mcpServers: servers,
                slashCommands: (json["slash_commands"]?.arrayValue ?? []).compactMap(\.stringValue),
                tools: (json["tools"]?.arrayValue ?? []).compactMap(\.stringValue)
            ))
        case "permission_denied":
            return .permissionDenied(
                toolName: json["tool_name"]?.stringValue ?? "unknown tool",
                message: json["message"]?.stringValue ?? ""
            )
        default:
            return .other(json)
        }
    }

    private static func decodeAssistant(_ json: JSONValue) -> StreamEvent {
        let message = json["message"]
        let blocks = (message?["content"]?.arrayValue ?? []).map(decodeBlock)
        return .assistant(AssistantMessage(
            messageId: message?["id"]?.stringValue,
            parentToolUseId: json["parent_tool_use_id"]?.stringValue,
            blocks: blocks,
            error: json["error"]?.stringValue
        ))
    }

    private static func decodeBlock(_ block: JSONValue) -> ContentBlock {
        let type = block["type"]?.stringValue ?? ""
        switch type {
        case "text":
            return .text(block["text"]?.stringValue ?? "")
        case "thinking":
            return .thinking(block["thinking"]?.stringValue ?? "")
        case "tool_use", "server_tool_use", "mcp_tool_use":
            return .toolUse(
                id: block["id"]?.stringValue ?? "",
                name: block["name"]?.stringValue ?? "",
                input: block["input"] ?? .object([:])
            )
        default:
            return .other(type: type)
        }
    }

    private static func decodeUser(_ json: JSONValue) -> StreamEvent {
        // User events in the output stream carry tool results. Plain-text echoes of our own
        // messages only appear with --replay-user-messages, which the app doesn't use.
        let content = json["message"]?["content"]?.arrayValue ?? []
        let results = content.compactMap { block -> ToolResult? in
            guard block["type"]?.stringValue == "tool_result",
                  let id = block["tool_use_id"]?.stringValue else { return nil }
            return ToolResult(
                toolUseId: id,
                isError: block["is_error"]?.boolValue ?? false,
                text: toolResultText(block["content"])
            )
        }
        if results.isEmpty { return .other(json) }
        return .toolResults(results, parentToolUseId: json["parent_tool_use_id"]?.stringValue)
    }

    /// Tool result content is either a string or a list of content blocks.
    static func toolResultText(_ content: JSONValue?) -> String {
        guard let content else { return "" }
        if let s = content.stringValue { return s }
        return (content.arrayValue ?? [])
            .compactMap { $0["type"]?.stringValue == "text" ? $0["text"]?.stringValue : nil }
            .joined(separator: "\n")
    }

    private static func decodeStreamEvent(_ json: JSONValue) -> StreamEvent {
        let event = json["event"]
        if event?["type"]?.stringValue == "content_block_delta",
           event?["delta"]?["type"]?.stringValue == "text_delta",
           let text = event?["delta"]?["text"]?.stringValue
        {
            return .textDelta(text, parentToolUseId: json["parent_tool_use_id"]?.stringValue)
        }
        return .other(json)
    }

    private static func decodeResult(_ json: JSONValue) -> TurnResult {
        let denials = (json["permission_denials"]?.arrayValue ?? []).map { d in
            PermissionDenial(
                toolName: d["tool_name"]?.stringValue ?? "unknown tool",
                toolUseId: d["tool_use_id"]?.stringValue,
                toolInput: d["tool_input"]
            )
        }
        return TurnResult(
            subtype: json["subtype"]?.stringValue ?? "",
            isError: json["is_error"]?.boolValue ?? false,
            sessionId: json["session_id"]?.stringValue,
            resultText: json["result"]?.stringValue,
            durationMs: json["duration_ms"]?.intValue,
            numTurns: json["num_turns"]?.intValue,
            totalCostUSD: json["total_cost_usd"]?.doubleValue,
            permissionDenials: denials,
            errors: (json["errors"]?.arrayValue ?? []).compactMap(\.stringValue)
        )
    }

    private static func decodeControlRequest(_ json: JSONValue) -> StreamEvent {
        guard let requestId = json["request_id"]?.stringValue, let request = json["request"] else {
            return .other(json)
        }
        let subtype = request["subtype"]?.stringValue ?? ""
        guard subtype == "can_use_tool" else {
            return .unsupportedControlRequest(requestId: requestId, subtype: subtype)
        }
        return .permissionRequest(PermissionRequest(
            requestId: requestId,
            toolName: request["tool_name"]?.stringValue ?? "",
            input: request["input"] ?? .object([:]),
            toolUseId: request["tool_use_id"]?.stringValue,
            title: request["title"]?.stringValue,
            displayName: request["display_name"]?.stringValue,
            description: request["description"]?.stringValue,
            decisionReason: request["decision_reason"]?.stringValue,
            blockedPath: request["blocked_path"]?.stringValue,
            agentId: request["agent_id"]?.stringValue,
            suggestions: request["permission_suggestions"]?.arrayValue ?? [],
            suppressAlwaysAllow: request["suppress_always_allow_rule"]?.boolValue ?? false
        ))
    }
}
