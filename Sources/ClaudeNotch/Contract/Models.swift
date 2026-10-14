import Foundation

// FROZEN CONTRACT — shared by Core (A), UI (B) and Integration (C). Coordinate before changing.

typealias SessionID = String

/// Ordered by priority (DESIGN: approval > question > error > done > working).
/// `attention` = "Waiting for you" notifications (idle_prompt, unheld elicitation).
enum SessionStatus: Int, Comparable, Sendable, CaseIterable {
    case idle = 0, working, done, error, attention, question, approval
    static func < (a: SessionStatus, b: SessionStatus) -> Bool { a.rawValue < b.rawValue }
}

struct TerminalHint: Equatable, Sendable {
    var bundleID: String?      // from X-Claude-Notch-Bundle header (__CFBundleIdentifier)
    var termProgram: String?   // from X-Claude-Notch-Term header (TERM_PROGRAM)
    static let unknown = TerminalHint(bundleID: nil, termProgram: nil)
}

struct SessionInfo: Identifiable, Equatable, Sendable {
    let id: SessionID
    var cwd: String
    var projectName: String          // URL(fileURLWithPath: cwd).lastPathComponent
    var status: SessionStatus
    var activity: String?            // "Running Bash", "Thinking", "Waiting for you", "Finished"
    var activityStartedAt: Date      // UI renders elapsed ("2m")
    var startedAt: Date
    var lastEventAt: Date
    var pendingItemCount: Int        // pending approvals+questions in this session
    var permissionMode: String?
    var terminal: TerminalHint
    var shortID: String { String(id.prefix(6)) }
}

struct ApprovalRequest: Equatable, Sendable {
    let toolName: String             // raw, e.g. "Bash", "mcp__github__create_issue"
    let displayToolName: String      // "Bash", "github · create_issue"
    let headline: String             // "Claude wants to run" / "Claude wants to edit" / "Claude wants to use"
    let summary: String              // one line: first command line, file path, url, …
    let detail: String?              // full text for CodeBlock (command, path, pretty JSON)
    let toolInput: JSONValue
    let suggestions: [JSONValue]     // raw permission_suggestions
    var canAlwaysAllow: Bool { !suggestions.isEmpty }
}

struct QuestionOption: Equatable, Sendable, Identifiable {
    var id: String { label }
    let label: String
    let description: String?
}

struct QuestionPrompt: Equatable, Sendable, Identifiable {
    var id: String { question }
    let question: String
    let header: String?
    let options: [QuestionOption]
    let multiSelect: Bool
}

struct QuestionRequest: Equatable, Sendable {
    let questions: [QuestionPrompt]  // 1…4
}

struct AttentionInfo: Equatable, Sendable {
    let title: String
    let message: String
    let notificationType: String?
}

struct DoneInfo: Equatable, Sendable {
    let summary: String?             // first non-empty line of last_assistant_message
}

struct ErrorInfo: Equatable, Sendable {
    let title: String
    let message: String
}

enum Resolution: Equatable, Sendable {
    case allowed, alwaysAllowed, denied, answered
    case answeredInTerminal          // also used for hook timeout and client disconnect
    case handedOff                   // user clicked "Answer in terminal"
    case dismissed, expired

    /// DESIGN copy.
    var label: String {
        switch self {
        case .allowed, .alwaysAllowed: return "Allowed"
        case .denied: return "Denied"
        case .answered: return "Answered"
        case .answeredInTerminal, .handedOff: return "Answered in terminal"
        case .dismissed, .expired: return ""
        }
    }
}

enum ItemState: Equatable, Sendable {
    case pending
    case resolved(Resolution, at: Date)
}

struct NotchItem: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case approval(ApprovalRequest)
        case question(QuestionRequest)
        case attention(AttentionInfo)
        case done(DoneInfo)
        case error(ErrorInfo)
    }

    let id: UUID
    let sessionID: SessionID
    let projectName: String
    let cwd: String
    let createdAt: Date
    let kind: Kind
    var state: ItemState

    var priority: SessionStatus {
        switch kind {
        case .approval: return .approval
        case .question: return .question
        case .attention: return .attention
        case .error: return .error
        case .done: return .done
        }
    }

    /// Approvals/questions hold an HTTP request open.
    var isBlocking: Bool {
        switch kind {
        case .approval, .question: return true
        default: return false
        }
    }

    var isPending: Bool { state == .pending }
}

enum ApprovalDecision: Equatable, Sendable {
    case allow
    case allowAlways                  // allow + updatedPermissions = suggestions
    case deny(message: String?)
}

/// question text → selected label; multiSelect labels joined with ", ".
typealias QuestionAnswers = [String: String]

enum ServerState: Equatable, Sendable {
    case stopped
    case listening(port: UInt16)
    case failed(message: String)      // e.g. "Port 41817 is in use"
}

enum DisplayPreference: String, CaseIterable, Codable, Sendable {
    case builtIn      // notched built-in display, else main
    case main         // NSScreen.main
    case mouse        // screen containing mouse at the time of each new event
}

enum NotchTiming {
    static let peekDuration: TimeInterval = 4
    static let doneLifetime: TimeInterval = 6          // done/error/attention fade
    static let resolvedLinger: TimeInterval = 1.5      // "Allowed"/"Answered in terminal" shown before removal
    static let hoverCollapseGrace: TimeInterval = 0.6
    static let defaultHoldTimeout: TimeInterval = 110  // < hook timeout 120
    static let hookTimeout: Int = 120
    static let observeHookTimeout: Int = 5
}
