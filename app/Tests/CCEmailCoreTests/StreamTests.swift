import Foundation
import Testing
@testable import CCEmailCore

@Suite struct StreamDecoderTests {
    @Test func joinsLinesSplitAcrossReads() {
        var decoder = StreamDecoder()
        let line = #"{"type":"result","subtype":"success","is_error":false,"result":"ok","session_id":"s1","permission_denials":[]}"# + "\n"
        let bytes = Data(line.utf8)
        let mid = bytes.count / 2
        #expect(decoder.feed(bytes.prefix(mid)).isEmpty)
        let events = decoder.feed(bytes.suffix(from: mid))
        #expect(events.count == 1)
        guard case .result(let r) = events.first else { Issue.record("expected result"); return }
        #expect(r.resultText == "ok")
        #expect(r.sessionId == "s1")
    }

    @Test func splitsMultipleLinesInOneChunk() {
        var decoder = StreamDecoder()
        let chunk = """
            {"type":"system","subtype":"hook_started"}
            {"type":"control_cancel_request","request_id":"r9"}

            not json
            """ + "\n"
        let events = decoder.feed(Data(chunk.utf8))
        #expect(events.count == 3)
        #expect(events[1] == .controlCancel(requestId: "r9"))
        #expect(events[2] == .unparsable("not json"))
    }

    @Test func holdsSplitMultibyteCharacter() {
        var decoder = StreamDecoder()
        let line = #"{"type":"assistant","message":{"id":"m1","content":[{"type":"text","text":"✓ done"}]},"parent_tool_use_id":null}"# + "\n"
        let bytes = Data(line.utf8)
        let check = bytes.firstIndex(of: 0xE2)!  // first byte of ✓
        #expect(decoder.feed(bytes[..<(check + 1)]).isEmpty)
        let events = decoder.feed(bytes[(check + 1)...])
        guard case .assistant(let m) = events.first else { Issue.record("expected assistant"); return }
        #expect(m.blocks == [.text("✓ done")])
    }

    @Test func finishDecodesUnterminatedLine() {
        var decoder = StreamDecoder()
        #expect(decoder.feed(Data(#"{"type":"control_cancel_request","request_id":"x"}"#.utf8)).isEmpty)
        #expect(decoder.finish() == [.controlCancel(requestId: "x")])
    }
}

@Suite struct StreamEventTests {
    @Test func decodesInit() {
        let event = StreamEvent.decode(line: """
            {"type":"system","subtype":"init","session_id":"abc","model":"claude-opus-5-5","cwd":"/tmp/w",\
            "claude_code_version":"2.1.295","permissionMode":"default","apiKeySource":"none","tools":["Read","Bash"],\
            "mcp_servers":[{"name":"claude.ai Gmail","status":"connected"}],"slash_commands":["summary","file-away"]}
            """)
        guard case .initialized(let info) = event else { Issue.record("expected init"); return }
        #expect(info.sessionId == "abc")
        #expect(info.mcpServers == [MCPServerStatus(name: "claude.ai Gmail", status: "connected")])
        #expect(info.slashCommands == ["summary", "file-away"])
        #expect(info.usesClaudeCodeLogin)
    }

    @Test func flagsAPIKeySessions() {
        let event = StreamEvent.decode(line: #"{"type":"system","subtype":"init","session_id":"s","apiKeySource":"user"}"#)
        guard case .initialized(let info) = event else { Issue.record("expected init"); return }
        #expect(!info.usesClaudeCodeLogin)
        let missing = StreamEvent.decode(line: #"{"type":"system","subtype":"init","session_id":"s"}"#)
        guard case .initialized(let info2) = missing else { Issue.record("expected init"); return }
        #expect(!info2.usesClaudeCodeLogin)
    }

    @Test func decodesAssistantToolUseWithParent() {
        let event = StreamEvent.decode(line: """
            {"type":"assistant","parent_tool_use_id":"toolu_parent","message":{"id":"msg_1","content":[\
            {"type":"text","text":"Searching"},\
            {"type":"tool_use","id":"toolu_1","name":"mcp__claude_ai_Gmail__search_threads","input":{"query":"in:inbox"}}]}}
            """)
        guard case .assistant(let m) = event else { Issue.record("expected assistant"); return }
        #expect(m.parentToolUseId == "toolu_parent")
        #expect(m.messageId == "msg_1")
        #expect(m.blocks == [
            .text("Searching"),
            .toolUse(id: "toolu_1", name: "mcp__claude_ai_Gmail__search_threads", input: ["query": "in:inbox"]),
        ])
    }

    @Test func decodesToolResultsInBothContentShapes() {
        let event = StreamEvent.decode(line: """
            {"type":"user","parent_tool_use_id":null,"message":{"role":"user","content":[\
            {"type":"tool_result","tool_use_id":"t1","content":"plain"},\
            {"type":"tool_result","tool_use_id":"t2","is_error":true,"content":[{"type":"text","text":"a"},{"type":"text","text":"b"}]}]}}
            """)
        #expect(event == .toolResults([
            ToolResult(toolUseId: "t1", isError: false, text: "plain"),
            ToolResult(toolUseId: "t2", isError: true, text: "a\nb"),
        ], parentToolUseId: nil))
    }

    @Test func decodesTextDelta() {
        let event = StreamEvent.decode(line: """
            {"type":"stream_event","parent_tool_use_id":null,"event":{"type":"content_block_delta","index":0,\
            "delta":{"type":"text_delta","text":"Hel"}}}
            """)
        #expect(event == .textDelta("Hel", parentToolUseId: nil))
    }

    @Test func decodesPermissionRequest() {
        let event = StreamEvent.decode(line: """
            {"type":"control_request","request_id":"req-1","request":{"subtype":"can_use_tool",\
            "tool_name":"Bash","input":{"command":"remindctl add --title x"},"tool_use_id":"toolu_9",\
            "title":"Run remindctl?","permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"remindctl add:*"}],"behavior":"allow","destination":"session"}]}}
            """)
        guard case .permissionRequest(let req) = event else { Issue.record("expected permission request"); return }
        #expect(req.requestId == "req-1")
        #expect(req.toolName == "Bash")
        #expect(req.input["command"]?.stringValue == "remindctl add --title x")
        #expect(req.toolUseId == "toolu_9")
        #expect(req.title == "Run remindctl?")
        #expect(req.suggestions.count == 1)
        #expect(!req.isAskUserQuestion)
    }

    @Test func otherControlRequestsMustBeAnswered() {
        let event = StreamEvent.decode(line: """
            {"type":"control_request","request_id":"req-2","request":{"subtype":"elicitation"}}
            """)
        #expect(event == .unsupportedControlRequest(requestId: "req-2", subtype: "elicitation"))
    }

    @Test func decodesResultWithDenialsAndErrors() {
        let event = StreamEvent.decode(line: """
            {"type":"result","subtype":"error_during_execution","is_error":true,"duration_ms":1200,"num_turns":3,\
            "total_cost_usd":0.25,"session_id":"s","errors":["boom"],\
            "permission_denials":[{"tool_name":"Bash","tool_use_id":"t","tool_input":{"command":"ls"}}]}
            """)
        guard case .result(let r) = event else { Issue.record("expected result"); return }
        #expect(r.isError)
        #expect(r.durationMs == 1200)
        #expect(r.totalCostUSD == 0.25)
        #expect(r.errors == ["boom"])
        #expect(r.permissionDenials == [PermissionDenial(toolName: "Bash", toolUseId: "t", toolInput: ["command": "ls"])])
    }

    @Test func decodesControlResponse() {
        let event = StreamEvent.decode(line: """
            {"type":"control_response","response":{"subtype":"error","request_id":"ccemail-1","error":"nope"}}
            """)
        #expect(event == .controlResponse(requestId: "ccemail-1", success: false, payload: nil, error: "nope"))
    }
}

@Suite struct OutboundTests {
    private func roundTrip(_ value: JSONValue) throws -> JSONValue {
        let line = value.serialized()
        #expect(!line.contains("\n"))
        return try JSONValue.parse(line)
    }

    @Test func userMessage() throws {
        let json = try roundTrip(Outbound.userMessage("/summary", sessionId: "s1"))
        #expect(json == [
            "type": "user",
            "message": ["role": "user", "content": "/summary"],
            "parent_tool_use_id": nil,
            "session_id": "s1",
        ])
    }

    @Test func allowEchoesInputAndToolUseId() throws {
        let json = try roundTrip(Outbound.allow(requestId: "r1", toolUseId: "t1", updatedInput: ["command": "ls"]))
        #expect(json == [
            "type": "control_response",
            "response": [
                "subtype": "success",
                "request_id": "r1",
                "response": ["behavior": "allow", "updatedInput": ["command": "ls"], "toolUseID": "t1"],
            ],
        ])
    }

    @Test func deny() throws {
        let json = try roundTrip(Outbound.deny(requestId: "r1", toolUseId: nil, message: "User denied"))
        #expect(json["response"]?["response"] == ["behavior": "deny", "message": "User denied"])
    }

    @Test func interruptAndInitialize() throws {
        #expect(try roundTrip(Outbound.interrupt(requestId: "i1"))
            == ["type": "control_request", "request_id": "i1", "request": ["subtype": "interrupt", "cancel_queued": true]])
        #expect(try roundTrip(Outbound.initialize(requestId: "i0"))["request"] == ["subtype": "initialize"])
    }

    @Test func answeredQuestionsKeepsQuestions() {
        let input: JSONValue = ["questions": [["question": "Which?", "header": "Pick"]]]
        let updated = Outbound.answeredQuestions(input: input, answers: ["Which?": "A, B"])
        #expect(updated["questions"] == input["questions"])
        #expect(updated["answers"] == ["Which?": "A, B"])
    }
}

@Suite struct LaunchConfigTests {
    @Test func newSessionArguments() {
        let config = LaunchConfig(
            claudePath: "/bin/claude", workingDirectory: URL(fileURLWithPath: "/tmp"),
            sessionId: "uuid-1", resume: false, model: "sonnet", appendSystemPrompt: "hi",
            allowedTools: ["Edit(a)", "Write(a)"], includePartialMessages: false
        )
        #expect(config.arguments == [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--permission-prompt-tool", "stdio", "--session-id", "uuid-1",
            "--model", "sonnet", "--append-system-prompt", "hi", "--allowedTools", "Edit(a),Write(a)",
        ])
    }

    @Test func resumeAndEnvironment() {
        let config = LaunchConfig(
            claudePath: "/bin/claude", workingDirectory: URL(fileURLWithPath: "/tmp"),
            sessionId: "uuid-2", resume: true, path: "/custom/bin"
        )
        #expect(config.arguments.contains("--resume"))
        #expect(!config.arguments.contains("--session-id"))
        let env = config.environment(base: [
            "PATH": "/usr/bin", "CLAUDECODE": "1", "HOME": "/h",
            "ANTHROPIC_API_KEY": "sk-test", "ANTHROPIC_AUTH_TOKEN": "t", "CLAUDE_CODE_USE_BEDROCK": "1",
        ])
        #expect(env == ["PATH": "/custom/bin", "HOME": "/h"])
    }
}

@Suite struct AuthStatusTests {
    @Test func acceptsOnlyClaudeAILogin() throws {
        let login = AuthStatus(json: try JSONValue.parse(#"{"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"max"}"#))
        #expect(login.usesClaudeCodeLogin)
        let apiKey = AuthStatus(json: try JSONValue.parse(#"{"loggedIn":true,"authMethod":"api_key","apiKeySource":"ANTHROPIC_API_KEY"}"#))
        #expect(!apiKey.usesClaudeCodeLogin)
        let loggedOut = AuthStatus(json: try JSONValue.parse(#"{"loggedIn":false,"authMethod":"claude.ai"}"#))
        #expect(!loggedOut.usesClaudeCodeLogin)
    }
}

@Suite struct UsageTests {
    @Test func parsesPlanUsage() throws {
        let json = try JSONValue.parse("""
            {"subscription_type":"max","rate_limits_available":true,"rate_limits":{
              "five_hour":{"utilization":6,"resets_at":"2026-10-09T06:40:00.475604+00:00"},
              "seven_day":{"utilization":13.5,"resets_at":"2026-10-12T13:00:00+00:00"},
              "seven_day_opus":null}}
            """)
        let usage = try #require(PlanUsage(response: json, now: Date(timeIntervalSince1970: 0)))
        #expect(usage.session?.percent == 6)
        #expect(usage.weekly?.percent == 13.5)
        #expect(usage.subscriptionType == "max")
        #expect(usage.session?.resetsAt == ISO8601DateFormatter().date(from: "2026-10-09T06:40:00Z"))
        #expect(usage.weekly?.resetsAt == ISO8601DateFormatter().date(from: "2026-10-12T13:00:00Z"))
    }

    @Test func noPlanUsageForAPIKeysOrUnknownShapes() throws {
        #expect(PlanUsage(response: try JSONValue.parse(#"{"rate_limits_available":false,"rate_limits":null}"#)) == nil)
        #expect(PlanUsage(response: try JSONValue.parse(#"{"something":"else"}"#)) == nil)
    }

    @Test func parsesContextUsage() throws {
        let json = try JSONValue.parse(#"{"totalTokens":340000,"maxTokens":1000000,"percentage":34,"model":"claude-opus-5-5[1m]"}"#)
        let usage = try #require(ContextUsage(response: json))
        #expect(usage.percentage == 34)
        #expect(usage.maxTokens == 1_000_000)
        #expect(ContextUsage(response: try JSONValue.parse(#"{"error":"no session"}"#)) == nil)
    }

    @Test func modelOptionsPutOneMillionContextOpusFirstAndDropDefault() throws {
        let json = try JSONValue.parse("""
            {"models":[{"value":"default","displayName":"Default (recommended)"},
                       {"value":"opus","displayName":"Opus 5.5"},
                       {"value":"sonnet","displayName":"Sonnet 5.5"}]}
            """)
        let options = ModelCatalog.options(fromListModels: json)
        #expect(options.map(\.value) == ["opus[1m]", "opus", "sonnet"])
        #expect(options[0].displayName == "Opus 5.5 (1M context)")
        #expect(ModelCatalog.options(fromListModels: .object([:])) == ModelCatalog.fallback)
        #expect(ModelCatalog.displayName(for: "opus[1m]", in: []) == "Opus 5.5 (1M context)")
    }

    @Test func modelAndUsageRequests() throws {
        #expect(Outbound.setModel("sonnet", requestId: "m")["request"] == ["subtype": "set_model", "model": "sonnet"])
        #expect(Outbound.getUsage(requestId: "u")["request"] == ["subtype": "get_usage"])
    }

    @Test func probeConfigHasNoSessionFlag() {
        var config = LaunchConfig(claudePath: "/bin/claude", workingDirectory: URL(fileURLWithPath: "/tmp"),
                                  sessionId: "", resume: false, allowedTools: [], includePartialMessages: false)
        config.extraArguments = ["--strict-mcp-config"]
        #expect(!config.arguments.contains("--session-id"))
        #expect(config.arguments.last == "--strict-mcp-config")
    }
}
