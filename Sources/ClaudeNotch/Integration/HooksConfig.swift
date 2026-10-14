import Foundation

/// Generates the exact hooks JSON from PLAN §3.
struct HooksConfig: Equatable {
    var port: UInt16
    var token: String
    var includeTerminalHeaders: Bool

    static let marker = "/claude-notch/v1/"

    var baseURL: String { "http://127.0.0.1:\(port)/claude-notch/v1" }

    private var encodedToken: String {
        token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
    }

    /// One HTTP handler dictionary.
    func handler(path: String, timeout: Int) -> [String: Any] {
        var h: [String: Any] = ["type": "http", "timeout": timeout]
        if includeTerminalHeaders {
            h["url"] = "\(baseURL)/\(path)"
            h["headers"] = [
                "X-Claude-Notch-Token": token,
                "X-Claude-Notch-Term": "$TERM_PROGRAM",
                "X-Claude-Notch-Bundle": "$__CFBundleIdentifier",
            ]
            h["allowedEnvVars"] = ["TERM_PROGRAM", "__CFBundleIdentifier"]
        } else {
            // No header interpolation: authenticate through the query string instead.
            h["url"] = "\(baseURL)/\(path)?token=\(encodedToken)"
        }
        return h
    }

    private func group(matcher: String?, path: String, timeout: Int) -> [String: Any] {
        var g: [String: Any] = ["hooks": [handler(path: path, timeout: timeout)]]
        if let matcher = matcher { g["matcher"] = matcher }
        return g
    }

    /// event name → matcher groups we own.
    func eventGroups() -> [String: [[String: Any]]] {
        let hold = NotchTiming.hookTimeout
        let observe = NotchTiming.observeHookTimeout
        func observed(_ matcher: String?) -> [[String: Any]] {
            [group(matcher: matcher, path: "event", timeout: observe)]
        }
        return [
            "PermissionRequest": [group(matcher: "*", path: "hook", timeout: hold)],
            "PreToolUse": [
                group(matcher: "AskUserQuestion", path: "hook", timeout: hold),
                group(matcher: "*", path: "event", timeout: observe),
            ],
            "PostToolUse": observed("*"),
            "PostToolUseFailure": observed("*"),
            "Notification": observed(nil),
            "UserPromptSubmit": observed(nil),
            "Stop": observed(nil),
            "SubagentStop": observed(nil),
            "SessionStart": observed(nil),
            "SessionEnd": observed(nil),
        ]
    }

    /// Full document fragment: `{"hooks": {...}}`.
    func document() -> [String: Any] {
        ["hooks": eventGroups()]
    }

    /// Number of handlers we install.
    var handlerCount: Int {
        eventGroups().values.reduce(0) { $0 + $1.count }
    }
}
