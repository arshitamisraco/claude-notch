import Foundation

enum AuthResult: Equatable, Sendable {
    case ok
    case reject(status: Int, message: String)
}

/// Method/path/Origin/Host/Content-Type/token checks (PLAN §4).
enum RequestAuthenticator {
    static let hookPath: String = "/claude-notch/v1/hook"
    static let eventPath: String = "/claude-notch/v1/event"
    static let tokenHeader: String = "x-claude-notch-token"
    static let termHeader: String = "x-claude-notch-term"
    static let bundleHeader: String = "x-claude-notch-bundle"

    static func authenticate(_ request: HTTPRequest, port: UInt16, token: String) -> AuthResult {
        if request.method != "POST" {
            return .reject(status: 405, message: "method not allowed")
        }
        if request.path != hookPath && request.path != eventPath {
            return .reject(status: 404, message: "not found")
        }
        if request.headers["origin"] != nil || request.headers["sec-fetch-site"] != nil {
            return .reject(status: 403, message: "forbidden")
        }
        let host: String = (request.headers["host"] ?? "").lowercased()
        if host != "127.0.0.1:\(port)" && host != "localhost:\(port)" {
            return .reject(status: 403, message: "forbidden host")
        }
        let contentType: String = (request.headers["content-type"] ?? "").lowercased()
        if !contentType.hasPrefix("application/json") {
            return .reject(status: 415, message: "unsupported media type")
        }
        guard let provided = providedToken(request), constantTimeEquals(provided, token) else {
            return .reject(status: 401, message: "unauthorized")
        }
        return .ok
    }

    /// Header value (unless it starts with "$", meaning un-interpolated) or `?token=`.
    static func providedToken(_ request: HTTPRequest) -> String? {
        if let h = cleanHeader(request.headers[tokenHeader]) { return h }
        if let q = request.query["token"], !q.isEmpty { return q }
        return nil
    }

    static func terminalHint(from request: HTTPRequest) -> TerminalHint {
        return TerminalHint(
            bundleID: cleanHeader(request.headers[bundleHeader]),
            termProgram: cleanHeader(request.headers[termHeader])
        )
    }

    /// nil when missing, empty or an un-interpolated `$VAR`.
    static func cleanHeader(_ value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return nil }
        if v.hasPrefix("$") { return nil }
        return v
    }

    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x: [UInt8] = Array(a.utf8)
        let y: [UInt8] = Array(b.utf8)
        if x.isEmpty || y.isEmpty { return false }
        var diff: Int = x.count ^ y.count
        let n: Int = max(x.count, y.count)
        var i: Int = 0
        while i < n {
            let p: UInt8 = i < x.count ? x[i] : 0
            let q: UInt8 = i < y.count ? y[i] : 0
            diff |= Int(p ^ q)
            i += 1
        }
        return diff == 0
    }
}
