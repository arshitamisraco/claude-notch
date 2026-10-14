import Foundation

/// A parsed HTTP/1.1 request. Header names are lowercased.
struct HTTPRequest: Equatable, Sendable {
    var method: String
    var target: String
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var body: Data

    func header(_ name: String) -> String? {
        return headers[name.lowercased()]
    }
}

enum HTTPParseError: Error, Equatable, Sendable {
    case malformed(String)
    case headerTooLarge
    case bodyTooLarge
}

enum HTTPParseResult: Equatable, Sendable {
    case needMore
    case complete(HTTPRequest, consumed: Int)
    case failure(HTTPParseError)
}

/// Stateless incremental parser: call with the full accumulated buffer each time.
enum HTTPRequestParser {
    static let maxBodyBytes: Int = 8 * 1024 * 1024
    static let maxHeaderBytes: Int = 64 * 1024

    private static let crlfcrlf: Data = Data([13, 10, 13, 10])
    private static let crlf: Data = Data([13, 10])

    private enum ChunkResult {
        case needMore
        case ok(Data, Int)
        case fail(HTTPParseError)
    }

    static func parse(_ input: Data) -> HTTPParseResult {
        let data: Data = input.startIndex == 0 ? input : Data(input)

        guard let sepRange = data.range(of: crlfcrlf) else {
            if data.count > maxHeaderBytes { return .failure(.headerTooLarge) }
            return .needMore
        }
        if sepRange.lowerBound > maxHeaderBytes { return .failure(.headerTooLarge) }

        let headData: Data = data.subdata(in: 0..<sepRange.lowerBound)
        let headText: String = String(data: headData, encoding: .utf8)
            ?? String(data: headData, encoding: .isoLatin1)
            ?? ""
        let lines: [String] = headText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            return .failure(.malformed("empty request line"))
        }
        let parts: [String] = requestLine.split(separator: " ", omittingEmptySubsequences: true).map { String($0) }
        guard parts.count == 3 else { return .failure(.malformed("bad request line")) }
        let method: String = parts[0].uppercased()
        let target: String = parts[1]
        let version: String = parts[2]
        guard version == "HTTP/1.1" || version == "HTTP/1.0" else {
            return .failure(.malformed("unsupported version"))
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { continue }
            guard let colon = line.firstIndex(of: ":") else {
                return .failure(.malformed("bad header line"))
            }
            let name: String = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value: String = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name.isEmpty { return .failure(.malformed("empty header name")) }
            headers[name] = value
        }

        let bodyStart: Int = sepRange.upperBound
        var body: Data = Data()
        var consumed: Int = bodyStart

        let transferEncoding: String = (headers["transfer-encoding"] ?? "").lowercased()
        if transferEncoding.contains("chunked") {
            switch parseChunked(data, from: bodyStart) {
            case .needMore: return .needMore
            case .fail(let e): return .failure(e)
            case .ok(let b, let end):
                body = b
                consumed = end
            }
        } else if let clText = headers["content-length"] {
            guard let length = Int(clText.trimmingCharacters(in: .whitespaces)), length >= 0 else {
                return .failure(.malformed("bad content-length"))
            }
            if length > maxBodyBytes { return .failure(.bodyTooLarge) }
            if data.count - bodyStart < length { return .needMore }
            body = data.subdata(in: bodyStart..<(bodyStart + length))
            consumed = bodyStart + length
        }

        var path: String = target
        var query: [String: String] = [:]
        if let q = target.firstIndex(of: "?") {
            path = String(target[target.startIndex..<q])
            query = parseQuery(String(target[target.index(after: q)...]))
        }

        let request = HTTPRequest(method: method, target: target, path: path, query: query, headers: headers, body: body)
        return .complete(request, consumed: consumed)
    }

    static func parseQuery(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in text.split(separator: "&", omittingEmptySubsequences: true) {
            let kv: [Substring] = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let first = kv.first else { continue }
            let rawKey: String = String(first)
            let rawValue: String = kv.count > 1 ? String(kv[1]) : ""
            let key: String = rawKey.removingPercentEncoding ?? rawKey
            let value: String = rawValue.removingPercentEncoding ?? rawValue
            if result[key] == nil { result[key] = value }
        }
        return result
    }

    private static func parseChunked(_ data: Data, from start: Int) -> ChunkResult {
        var pos: Int = start
        var body = Data()
        while true {
            guard let lineEnd = data.range(of: crlf, in: pos..<data.count) else {
                if data.count - pos > 1024 { return .fail(.malformed("chunk size line too long")) }
                return .needMore
            }
            let sizeData: Data = data.subdata(in: pos..<lineEnd.lowerBound)
            var sizeText: String = String(data: sizeData, encoding: .utf8) ?? ""
            if let semi = sizeText.firstIndex(of: ";") {
                sizeText = String(sizeText[sizeText.startIndex..<semi])
            }
            sizeText = sizeText.trimmingCharacters(in: .whitespaces)
            guard let size = Int(sizeText, radix: 16), size >= 0 else {
                return .fail(.malformed("bad chunk size"))
            }
            pos = lineEnd.upperBound
            if size == 0 {
                // trailers until an empty line
                while true {
                    guard let tEnd = data.range(of: crlf, in: pos..<data.count) else { return .needMore }
                    let empty: Bool = tEnd.lowerBound == pos
                    pos = tEnd.upperBound
                    if empty { return .ok(body, pos) }
                }
            }
            if body.count + size > maxBodyBytes { return .fail(.bodyTooLarge) }
            if data.count < pos + size + 2 { return .needMore }
            body.append(data.subdata(in: pos..<(pos + size)))
            let term: Data = data.subdata(in: (pos + size)..<(pos + size + 2))
            if term != crlf { return .fail(.malformed("missing chunk terminator")) }
            pos += size + 2
        }
    }
}
