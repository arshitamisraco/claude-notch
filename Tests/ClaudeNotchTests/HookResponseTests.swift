import XCTest
@testable import ClaudeNotch

final class HookResponseTests: XCTestCase {
    func testEmpty() {
        XCTAssertEqual(String(data: HookResponse.emptyData, encoding: .utf8), "{}")
        XCTAssertEqual(HookResponse.string(HookResponse.empty()), "{}")
    }

    func testAllowExactJSON() {
        XCTAssertEqual(
            HookResponse.string(HookResponse.allow()),
            #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#
        )
    }

    func testAllowAlwaysIncludesSuggestions() {
        let suggestion: JSONValue = .object(["type": .string("addRules")])
        XCTAssertEqual(
            HookResponse.string(HookResponse.allowAlways(suggestions: [suggestion])),
            #"{"hookSpecificOutput":{"decision":{"behavior":"allow","updatedPermissions":[{"type":"addRules"}]},"hookEventName":"PermissionRequest"}}"#
        )
        XCTAssertEqual(HookResponse.allowAlways(suggestions: []), HookResponse.allow())
    }

    func testDeny() {
        XCTAssertEqual(
            HookResponse.string(HookResponse.deny(message: nil)),
            #"{"hookSpecificOutput":{"decision":{"behavior":"deny","interrupt":false,"message":"Denied from Claude Notch"},"hookEventName":"PermissionRequest"}}"#
        )
        let custom = HookResponse.deny(message: "nope")
        XCTAssertEqual(custom["hookSpecificOutput"]?["decision"]?["message"]?.stringValue, "nope")
    }

    func testAnswerEchoesOriginalInputWithAnswers() {
        let original: JSONValue = .object([
            "questions": .array([.object(["question": .string("Which?"), "options": .array([.object(["label": .string("A")])])])]),
            "metadata": .object(["k": .string("v")])
        ])
        let out = HookResponse.answer(toolInput: original, answers: ["Which?": "A"])
        let hso = out["hookSpecificOutput"]
        XCTAssertEqual(hso?["hookEventName"]?.stringValue, "PreToolUse")
        XCTAssertEqual(hso?["permissionDecision"]?.stringValue, "allow")
        let updated = hso?["updatedInput"]
        XCTAssertEqual(updated?["answers"], .object(["Which?": .string("A")]))
        XCTAssertEqual(updated?["questions"], original["questions"])
        XCTAssertEqual(updated?["metadata"], original["metadata"])
    }

    func testValueForDecision() {
        XCTAssertEqual(HookResponse.value(for: .allow, suggestions: []), HookResponse.allow())
        XCTAssertEqual(HookResponse.value(for: .deny(message: "x"), suggestions: []), HookResponse.deny(message: "x"))
    }
}
