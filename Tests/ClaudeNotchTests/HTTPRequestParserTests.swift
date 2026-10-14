import XCTest
@testable import ClaudeNotch

final class HTTPRequestParserTests: XCTestCase {
    private func raw(_ s: String) -> Data { return Data(s.utf8) }

    private func makeRequest(path: String = "/claude-notch/v1/hook", host: String = "127.0.0.1:41817",
                             extra: [String: String] = [:], method: String = "POST", body: String = "{}") -> HTTPRequest {
        var headers: [String: String] = ["host": host, "content-type": "application/json", "x-claude-notch-token": "secret-token"]
        for (k, v) in extra { headers[k.lowercased()] = v }
        return HTTPRequest(method: method, target: path, path: path, query: [:], headers: headers, body: Data(body.utf8))
    }

    func testParsesSimplePost() {
        let body = #"{"a":1}"#
        let text = "POST /claude-notch/v1/hook?token=abc%2Bd&x=1 HTTP/1.1\r\nHost: 127.0.0.1:41817\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        guard case .complete(let req, let consumed) = HTTPRequestParser.parse(raw(text)) else { return XCTFail("expected complete") }
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.path, "/claude-notch/v1/hook")
        XCTAssertEqual(req.query["token"], "abc+d")
        XCTAssertEqual(req.query["x"], "1")
        XCTAssertEqual(req.header("Content-Type"), "application/json")
        XCTAssertEqual(String(data: req.body, encoding: .utf8), body)
        XCTAssertEqual(consumed, text.utf8.count)
    }

    func testNeedMoreOnPartialHeadersAndBody() {
        XCTAssertEqual(HTTPRequestParser.parse(raw("POST /x HTTP/1.1\r\nHost: a")), .needMore)
        let partial = "POST /x HTTP/1.1\r\nContent-Length: 10\r\n\r\n12345"
        XCTAssertEqual(HTTPRequestParser.parse(raw(partial)), .needMore)
    }

    func testIncrementalByteByByte() {
        let text = "POST /x HTTP/1.1\r\nContent-Length: 3\r\n\r\nabc"
        let bytes = Array(text.utf8)
        var buffer = Data()
        var result: HTTPParseResult = .needMore
        for b in bytes {
            buffer.append(b)
            result = HTTPRequestParser.parse(buffer)
            if case .complete = result { break }
        }
        guard case .complete(let req, _) = result else { return XCTFail("expected complete") }
        XCTAssertEqual(String(data: req.body, encoding: .utf8), "abc")
    }

    func testChunkedBody() {
        let text = "POST /x HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6;ext=1\r\n world\r\n0\r\n\r\n"
        guard case .complete(let req, let consumed) = HTTPRequestParser.parse(raw(text)) else { return XCTFail("expected complete") }
        XCTAssertEqual(String(data: req.body, encoding: .utf8), "hello world")
        XCTAssertEqual(consumed, text.utf8.count)
        let incomplete = "POST /x HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhel"
        XCTAssertEqual(HTTPRequestParser.parse(raw(incomplete)), .needMore)
    }

    func testBodyTooLarge() {
        let text = "POST /x HTTP/1.1\r\nContent-Length: \(HTTPRequestParser.maxBodyBytes + 1)\r\n\r\n"
        XCTAssertEqual(HTTPRequestParser.parse(raw(text)), .failure(.bodyTooLarge))
    }

    func testMalformed() {
        if case .failure = HTTPRequestParser.parse(raw("GARBAGE\r\n\r\n")) {} else { XCTFail("expected failure") }
        if case .failure = HTTPRequestParser.parse(raw("POST /x HTTP/1.1\r\nContent-Length: abc\r\n\r\n")) {} else { XCTFail("expected failure") }
        if case .failure = HTTPRequestParser.parse(raw("POST /x HTTP/1.1\r\nNoColonHere\r\n\r\n")) {} else { XCTFail("expected failure") }
    }

    func testHeaderTooLarge() {
        let big = Data(repeating: 65, count: HTTPRequestParser.maxHeaderBytes + 10)
        XCTAssertEqual(HTTPRequestParser.parse(big), .failure(.headerTooLarge))
    }

    // MARK: authenticator

    func testAuthOK() {
        XCTAssertEqual(RequestAuthenticator.authenticate(makeRequest(), port: 41817, token: "secret-token"), .ok)
        XCTAssertEqual(RequestAuthenticator.authenticate(makeRequest(host: "localhost:41817"), port: 41817, token: "secret-token"), .ok)
    }

    func testAuthRejections() {
        func status(_ r: HTTPRequest, token: String = "secret-token") -> Int? {
            if case .reject(let s, _) = RequestAuthenticator.authenticate(r, port: 41817, token: token) { return s }
            return nil
        }
        XCTAssertEqual(status(makeRequest(method: "GET")), 405)
        XCTAssertEqual(status(makeRequest(method: "OPTIONS")), 405)
        XCTAssertEqual(status(makeRequest(path: "/other")), 404)
        XCTAssertEqual(status(makeRequest(extra: ["Origin": "http://evil.com"])), 403)
        XCTAssertEqual(status(makeRequest(extra: ["Sec-Fetch-Site": "cross-site"])), 403)
        XCTAssertEqual(status(makeRequest(host: "evil.com:41817")), 403)
        XCTAssertEqual(status(makeRequest(host: "127.0.0.1:1234")), 403)
        XCTAssertEqual(status(makeRequest(extra: ["Content-Type": "text/plain"])), 415)
        XCTAssertEqual(status(makeRequest(extra: ["X-Claude-Notch-Token": "wrong"])), 401)
        XCTAssertEqual(status(makeRequest(), token: ""), 401)
    }

    func testTokenViaQueryAndDollarHeader() {
        var r = makeRequest(extra: ["X-Claude-Notch-Token": "$CLAUDE_NOTCH_TOKEN"])
        XCTAssertEqual(RequestAuthenticator.authenticate(r, port: 41817, token: "secret-token"), .reject(status: 401, message: "unauthorized"))
        r.query["token"] = "secret-token"
        XCTAssertEqual(RequestAuthenticator.authenticate(r, port: 41817, token: "secret-token"), .ok)
    }

    func testTerminalHintIgnoresUninterpolated() {
        let r = makeRequest(extra: ["X-Claude-Notch-Term": "$TERM_PROGRAM", "X-Claude-Notch-Bundle": "com.apple.Terminal"])
        let hint = RequestAuthenticator.terminalHint(from: r)
        XCTAssertNil(hint.termProgram)
        XCTAssertEqual(hint.bundleID, "com.apple.Terminal")
    }

    func testConstantTimeEquals() {
        XCTAssertTrue(RequestAuthenticator.constantTimeEquals("abc", "abc"))
        XCTAssertFalse(RequestAuthenticator.constantTimeEquals("abc", "abd"))
        XCTAssertFalse(RequestAuthenticator.constantTimeEquals("abc", "abcd"))
        XCTAssertFalse(RequestAuthenticator.constantTimeEquals("", ""))
    }
}
