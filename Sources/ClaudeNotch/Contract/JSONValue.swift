import Foundation

/// Arbitrary JSON, used for hook fields whose shape we don't control (tool_input, tool_response, …).
/// FROZEN CONTRACT — coordinate before changing.
enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .number(let n):
            // Emit integral numbers without a fractional part.
            if n.rounded() == n, abs(n) < 9.0e15 {
                try container.encode(Int64(n))
            } else {
                try container.encode(n)
            }
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    /// Compact JSON text (sorted keys) – for CodeBlock fallback and fingerprints.
    func compactString() -> String {
        encoded(pretty: false)
    }

    /// Pretty JSON text (sorted keys) – for "Show more".
    func prettyString() -> String {
        encoded(pretty: true)
    }

    private func encoded(pretty: Bool) -> String {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { formatting.insert(.prettyPrinted) }
        encoder.outputFormatting = formatting
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return text
    }
}
