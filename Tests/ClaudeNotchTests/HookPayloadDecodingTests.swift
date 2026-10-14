import XCTest
@testable import ClaudeNotch

final class HookPayloadDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> HookPayload {
        return try JSONDecoder().decode(HookPayload.self, from: Data(json.utf8))
    }

    func testDecodesPermissionRequest() throws {
        let p = try decode("""
        {"session_id":"abc123","hook_event_name":"PermissionRequest","cwd":"/tmp/proj",
         "permission_mode":"default","tool_name":"Bash","tool_use_id":"toolu_1",
         "tool_input":{"command":"ls -la","description":"list"},
         "permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"ls:*"}]}]}
        """)
        XCTAssertEqual(p.sessionId, "abc123")
        XCTAssertEqual(p.event, .permissionRequest)
        XCTAssertEqual(p.toolName, "Bash")
        XCTAssertEqual(p.toolInput?["command"]?.stringValue, "ls -la")
        XCTAssertEqual(p.permissionSuggestions?.count, 1)
        XCTAssertEqual(p.toolUseId, "toolu_1")
    }

    func testMinimalPayload() throws {
        let p = try decode(#"{"session_id":"s","hook_event_name":"Stop"}"#)
        XCTAssertEqual(p.event, .stop)
        XCTAssertNil(p.cwd)
        XCTAssertNil(p.toolInput)
        XCTAssertNil(p.stopHookActive)
    }

    func testUnknownEventDecodes() throws {
        let p = try decode(#"{"session_id":"s","hook_event_name":"SomethingNew","extra":1}"#)
        XCTAssertEqual(p.event, .unknown)
    }

    func testMissingRequiredFieldsFail() {
        XCTAssertThrowsError(try decode(#"{"hook_event_name":"Stop"}"#))
        XCTAssertThrowsError(try decode(#"{"session_id":"s"}"#))
        XCTAssertThrowsError(try decode(#"{"session_id":"","hook_event_name":"Stop"}"#))
    }

    func testWrongTypesAreLenient() throws {
        let p = try decode(#"{"session_id":"s","hook_event_name":"Stop","cwd":5,"stop_hook_active":"yes","permission_suggestions":{"a":1}}"#)
        XCTAssertNil(p.cwd)
        XCTAssertNil(p.stopHookActive)
        XCTAssertNil(p.permissionSuggestions)
    }

    func testNotificationAndStopFields() throws {
        let n = try decode(#"{"session_id":"s","hook_event_name":"Notification","notification_type":"idle_prompt","message":"hi"}"#)
        XCTAssertEqual(n.notificationType, "idle_prompt")
        let s = try decode(#"{"session_id":"s","hook_event_name":"Stop","stop_hook_active":true,"last_assistant_message":"Done.\nMore"}"#)
        XCTAssertEqual(s.stopHookActive, true)
        XCTAssertEqual(ToolSummarizer.firstLine(s.lastAssistantMessage ?? ""), "Done.")
    }

    func testToolSummarizer() {
        let bash = ToolSummarizer.summarize(toolName: "Bash", toolInput: .object(["command": .string("\n  echo hi\nls")]))
        XCTAssertEqual(bash.headline, "Claude wants to run")
        XCTAssertEqual(bash.summary, "echo hi")
        let edit = ToolSummarizer.summarize(toolName: "Edit", toolInput: .object(["file_path": .string("/a/b.swift")]))
        XCTAssertEqual(edit.headline, "Claude wants to edit")
        XCTAssertEqual(edit.summary, "/a/b.swift")
        let mcp = ToolSummarizer.summarize(toolName: "mcp__github__create_issue", toolInput: .object(["title": .string("x")]))
        XCTAssertEqual(mcp.displayToolName, "github · create_issue")
        XCTAssertEqual(mcp.headline, "Claude wants to use")
        XCTAssertNotNil(mcp.detail)
        XCTAssertEqual(ToolSummarizer.fingerprint(toolName: "Bash", toolInput: .object(["a": .number(1)])), "Bash|{\"a\":1}")
    }

    func testHugeInputTruncated() {
        let big = String(repeating: "x", count: 50_000)
        let s = ToolSummarizer.summarize(toolName: "Bash", toolInput: .object(["command": .string(big)]))
        XCTAssertLessThanOrEqual(s.detail?.count ?? 0, ToolSummarizer.displayLimit + 1)
        XCTAssertLessThanOrEqual(s.summary.count, ToolSummarizer.summaryLimit + 1)
    }

    func testParseQuestions() throws {
        let input: JSONValue = .object(["questions": .array([
            .object(["question": .string("Which?"), "header": .string("Pick"), "multiSelect": .bool(true),
                     "options": .array([.object(["label": .string("A"), "description": .string("a")]),
                                        .object(["label": .string("B")])])])
        ])])
        let q = ToolSummarizer.parseQuestions(toolInput: input)
        XCTAssertEqual(q?.questions.count, 1)
        XCTAssertEqual(q?.questions.first?.options.map { $0.label }, ["A", "B"])
        XCTAssertEqual(q?.questions.first?.multiSelect, true)
        XCTAssertNil(ToolSummarizer.parseQuestions(toolInput: .object([:])))
        XCTAssertNil(ToolSummarizer.parseQuestions(toolInput: .object(["questions": .array([])])))
        XCTAssertNil(ToolSummarizer.parseQuestions(toolInput: .object(["questions": .array([.object(["question": .string("Q")])])])))
    }
}
