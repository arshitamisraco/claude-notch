import Foundation

enum HookEvent: String, Sendable {
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case postToolUseFailure = "PostToolUseFailure"
    case permissionRequest = "PermissionRequest"
    case notification = "Notification"
    case stop = "Stop"
    case subagentStop = "SubagentStop"
    case unknown = "__unknown__"
}

/// Superset of Claude Code hook input fields. Only `session_id` and `hook_event_name` are required;
/// every other field is decoded leniently (wrong types become nil).
struct HookPayload: Decodable, Equatable, Sendable {
    var sessionId: String
    var hookEventName: String
    var cwd: String?
    var transcriptPath: String?
    var permissionMode: String?
    var toolName: String?
    var toolInput: JSONValue?
    var toolResponse: JSONValue?
    var toolUseId: String?
    var permissionSuggestions: [JSONValue]?
    var message: String?
    var title: String?
    var notificationType: String?
    var prompt: String?
    var stopHookActive: Bool?
    var lastAssistantMessage: String?
    var reason: String?
    var source: String?
    var error: String?
    var isInterrupt: Bool?

    var event: HookEvent {
        return HookEvent(rawValue: hookEventName) ?? .unknown
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case hookEventName = "hook_event_name"
        case cwd
        case transcriptPath = "transcript_path"
        case permissionMode = "permission_mode"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolResponse = "tool_response"
        case toolUseId = "tool_use_id"
        case permissionSuggestions = "permission_suggestions"
        case message
        case title
        case notificationType = "notification_type"
        case prompt
        case stopHookActive = "stop_hook_active"
        case lastAssistantMessage = "last_assistant_message"
        case reason
        case source
        case error
        case isInterrupt = "is_interrupt"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let sid: String = try c.decode(String.self, forKey: .sessionId)
        let name: String = try c.decode(String.self, forKey: .hookEventName)
        if sid.isEmpty {
            throw DecodingError.dataCorruptedError(forKey: .sessionId, in: c, debugDescription: "empty session_id")
        }
        sessionId = sid
        hookEventName = name

        func str(_ key: CodingKeys) -> String? {
            let value: String?? = try? c.decodeIfPresent(String.self, forKey: key)
            if let outer = value { return outer }
            return nil
        }
        func bool(_ key: CodingKeys) -> Bool? {
            let value: Bool?? = try? c.decodeIfPresent(Bool.self, forKey: key)
            if let outer = value { return outer }
            return nil
        }
        func json(_ key: CodingKeys) -> JSONValue? {
            let value: JSONValue?? = try? c.decodeIfPresent(JSONValue.self, forKey: key)
            if let outer = value { return outer }
            return nil
        }

        cwd = str(.cwd)
        transcriptPath = str(.transcriptPath)
        permissionMode = str(.permissionMode)
        toolName = str(.toolName)
        toolInput = json(.toolInput)
        toolResponse = json(.toolResponse)
        toolUseId = str(.toolUseId)
        if let sug = json(.permissionSuggestions), case .array(let arr) = sug {
            permissionSuggestions = arr
        } else {
            permissionSuggestions = nil
        }
        message = str(.message)
        title = str(.title)
        notificationType = str(.notificationType)
        prompt = str(.prompt)
        stopHookActive = bool(.stopHookActive)
        lastAssistantMessage = str(.lastAssistantMessage)
        reason = str(.reason)
        source = str(.source)
        error = str(.error)
        isInterrupt = bool(.isInterrupt)
    }

    /// Convenience for tests and internal construction.
    init(
        sessionId: String,
        hookEventName: String,
        cwd: String? = nil,
        transcriptPath: String? = nil,
        permissionMode: String? = nil,
        toolName: String? = nil,
        toolInput: JSONValue? = nil,
        toolResponse: JSONValue? = nil,
        toolUseId: String? = nil,
        permissionSuggestions: [JSONValue]? = nil,
        message: String? = nil,
        title: String? = nil,
        notificationType: String? = nil,
        prompt: String? = nil,
        stopHookActive: Bool? = nil,
        lastAssistantMessage: String? = nil,
        reason: String? = nil,
        source: String? = nil,
        error: String? = nil,
        isInterrupt: Bool? = nil
    ) {
        self.sessionId = sessionId
        self.hookEventName = hookEventName
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.permissionMode = permissionMode
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolResponse = toolResponse
        self.toolUseId = toolUseId
        self.permissionSuggestions = permissionSuggestions
        self.message = message
        self.title = title
        self.notificationType = notificationType
        self.prompt = prompt
        self.stopHookActive = stopHookActive
        self.lastAssistantMessage = lastAssistantMessage
        self.reason = reason
        self.source = source
        self.error = error
        self.isInterrupt = isInterrupt
    }
}
