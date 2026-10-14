import Foundation

/// Builders for hook output JSON (PLAN §3 "Response bodies").
enum HookResponse {
    static let defaultDenyMessage: String = "Denied from Claude Notch"

    /// `{}`
    static let emptyData: Data = Data("{}".utf8)

    static func empty() -> JSONValue {
        return .object([:])
    }

    static func allow() -> JSONValue {
        return permissionRequest(decision: ["behavior": .string("allow")])
    }

    /// Allow + `updatedPermissions`. Falls back to plain allow when there are no suggestions.
    static func allowAlways(suggestions: [JSONValue]) -> JSONValue {
        if suggestions.isEmpty { return allow() }
        return permissionRequest(decision: [
            "behavior": .string("allow"),
            "updatedPermissions": .array(suggestions)
        ])
    }

    static func deny(message: String?) -> JSONValue {
        let text: String = (message?.isEmpty == false) ? (message ?? defaultDenyMessage) : defaultDenyMessage
        return permissionRequest(decision: [
            "behavior": .string("deny"),
            "message": .string(text),
            "interrupt": .bool(false)
        ])
    }

    /// PreToolUse allow with the ORIGINAL tool_input plus `answers`.
    static func answer(toolInput: JSONValue, answers: QuestionAnswers) -> JSONValue {
        var input: [String: JSONValue] = toolInput.objectValue ?? [:]
        var answerObject: [String: JSONValue] = [:]
        for (question, label) in answers {
            answerObject[question] = .string(label)
        }
        input["answers"] = .object(answerObject)
        return .object([
            "hookSpecificOutput": .object([
                "hookEventName": .string("PreToolUse"),
                "permissionDecision": .string("allow"),
                "updatedInput": .object(input)
            ])
        ])
    }

    static func value(for decision: ApprovalDecision, suggestions: [JSONValue]) -> JSONValue {
        switch decision {
        case .allow: return allow()
        case .allowAlways: return allowAlways(suggestions: suggestions)
        case .deny(let message): return deny(message: message)
        }
    }

    static func encode(_ value: JSONValue) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(value) { return data }
        return emptyData
    }

    static func string(_ value: JSONValue) -> String {
        return String(data: encode(value), encoding: .utf8) ?? "{}"
    }

    private static func permissionRequest(decision: [String: JSONValue]) -> JSONValue {
        return .object([
            "hookSpecificOutput": .object([
                "hookEventName": .string("PermissionRequest"),
                "decision": .object(decision)
            ])
        ])
    }
}
