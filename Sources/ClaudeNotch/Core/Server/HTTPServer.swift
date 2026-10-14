import Foundation
import Network
import os

struct HTTPResponse: Sendable {
    var status: Int
    var body: Data

    static func json(_ status: Int, _ body: Data) -> HTTPResponse {
        return HTTPResponse(status: status, body: body)
    }

    static func error(_ status: Int, _ message: String) -> HTTPResponse {
        let value: JSONValue = .object(["error": .string(message)])
        return HTTPResponse(status: status, body: HookResponse.encode(value))
    }

    var serialized: Data {
        var head: String = "HTTP/1.1 \(status) \(HTTPResponse.reason(status))\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        default: return "Error"
        }
    }
}

/// Loopback-only HTTP/1.1 server on NWListener. All mutable state is confined to `queue`.
final class HTTPServer: @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest, UUID) async -> HTTPResponse

    static let maxConnections: Int = 64
    static let headerTimeout: TimeInterval = 10

    fileprivate let port: UInt16
    fileprivate let token: String
    fileprivate let handler: Handler
    fileprivate let onDisconnect: @Sendable (UUID) -> Void
    private let onState: @Sendable (ServerState) -> Void
    fileprivate let queue = DispatchQueue(label: "dev.claudenotch.http")

    private var listener: NWListener?
    fileprivate var connections: [UUID: ServerConnection] = [:]
    private var stopped: Bool = false
    private let log = Logger(subsystem: "dev.claudenotch", category: "server")

    init(
        port: UInt16,
        token: String,
        handler: @escaping Handler,
        onDisconnect: @escaping @Sendable (UUID) -> Void,
        onState: @escaping @Sendable (ServerState) -> Void
    ) {
        self.port = port
        self.token = token
        self.handler = handler
        self.onDisconnect = onDisconnect
        self.onState = onState
    }

    func start() {
        queue.async { self.startOnQueue() }
    }

    /// Stops accepting immediately; open connections get a short grace period so released
    /// `{}` responses can be flushed.
    func stop() {
        queue.async {
            self.stopped = true
            self.listener?.cancel()
            self.listener = nil
            let open: [ServerConnection] = Array(self.connections.values)
            self.queue.asyncAfter(deadline: .now() + 0.5) {
                for c in open { c.cancel() }
            }
        }
    }

    private func startOnQueue() {
        if listener != nil { return }
        stopped = false
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            onState(.failed(message: "Invalid port \(port)"))
            return
        }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(IPv4Address.loopback), port: nwPort)
        let created: NWListener
        do {
            created = try NWListener(using: params)
        } catch {
            onState(.failed(message: "Could not listen on port \(port): \(error.localizedDescription)"))
            return
        }
        listener = created
        let boundPort: UInt16 = port
        created.stateUpdateHandler = { [weak self, weak created] (state: NWListener.State) in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.onState(.listening(port: created?.port?.rawValue ?? boundPort))
            case .failed(let error):
                self.onState(.failed(message: HTTPServer.describe(error, port: boundPort)))
                created?.cancel()
                if self.listener === created { self.listener = nil }
            case .waiting(let error):
                if case .posix(let code) = error, code == .EADDRINUSE {
                    self.onState(.failed(message: "Port \(boundPort) is in use"))
                }
            default:
                break
            }
        }
        created.newConnectionHandler = { [weak self] (connection: NWConnection) in
            self?.accept(connection)
        }
        created.start(queue: queue)
    }

    private static func describe(_ error: NWError, port: UInt16) -> String {
        if case .posix(let code) = error, code == .EADDRINUSE {
            return "Port \(port) is in use"
        }
        return "Server failed: \(error.localizedDescription)"
    }

    private func accept(_ connection: NWConnection) {
        if stopped || connections.count >= HTTPServer.maxConnections || !HTTPServer.isLoopback(connection.endpoint) {
            connection.cancel()
            return
        }
        let sc = ServerConnection(connection: connection, server: self)
        connections[sc.id] = sc
        sc.start()
    }

    private static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        if case .hostPort(let host, _) = endpoint {
            switch host {
            case .ipv4(let address): return address.isLoopback
            case .ipv6(let address): return address.isLoopback
            default: return false
            }
        }
        return false
    }

    fileprivate func removeConnection(_ id: UUID) {
        connections[id] = nil
    }
}

private final class ServerConnection: @unchecked Sendable {
    let id: UUID = UUID()
    private let connection: NWConnection
    private let server: HTTPServer
    private var buffer = Data()
    private var dispatched: Bool = false
    private var responded: Bool = false
    private var finished: Bool = false
    private var headerTimer: DispatchWorkItem?

    init(connection: NWConnection, server: HTTPServer) {
        self.connection = connection
        self.server = server
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] (state: NWConnection.State) in
            guard let self = self else { return }
            switch state {
            case .failed, .cancelled:
                self.end()
            default:
                break
            }
        }
        connection.start(queue: server.queue)
        let timer = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if !self.dispatched && !self.finished { self.connection.cancel() }
        }
        headerTimer = timer
        server.queue.asyncAfter(deadline: .now() + HTTPServer.headerTimeout, execute: timer)
        receive()
    }

    func cancel() {
        connection.cancel()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data: Data?, _: NWConnection.ContentContext?, isComplete: Bool, error: NWError?) in
            guard let self = self, !self.finished else { return }
            let dispatchedBefore: Bool = self.dispatched
            if let data = data, !data.isEmpty {
                self.didReceive(data)
            }
            if error != nil {
                self.connection.cancel()
                return
            }
            if isComplete {
                // EOF. If it arrived together with the final bytes of the request, treat it as a
                // half-close and keep waiting for our response; otherwise the peer is gone.
                if dispatchedBefore || !self.dispatched {
                    self.connection.cancel()
                }
                return
            }
            self.receive()
        }
    }

    private func didReceive(_ data: Data) {
        if dispatched { return }
        buffer.append(data)
        switch HTTPRequestParser.parse(buffer) {
        case .needMore:
            break
        case .failure(let error):
            dispatched = true
            headerTimer?.cancel()
            switch error {
            case .bodyTooLarge:
                respond(HTTPResponse.error(413, "payload too large"))
            case .headerTooLarge, .malformed:
                respond(HTTPResponse.error(400, "bad request"))
            }
        case .complete(let request, _):
            dispatched = true
            headerTimer?.cancel()
            buffer = Data()
            dispatch(request)
        }
    }

    private func dispatch(_ request: HTTPRequest) {
        switch RequestAuthenticator.authenticate(request, port: server.port, token: server.token) {
        case .reject(let status, let message):
            respond(HTTPResponse.error(status, message))
        case .ok:
            let handler = server.handler
            let requestID: UUID = id
            let queue = server.queue
            Task { [weak self] in
                let response: HTTPResponse = await handler(request, requestID)
                queue.async { self?.respond(response) }
            }
        }
    }

    private func respond(_ response: HTTPResponse) {
        if responded || finished { return }
        responded = true
        connection.send(
            content: response.serialized,
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed({ [weak self] (_: NWError?) in
                self?.connection.cancel()
            })
        )
    }

    private func end() {
        if finished { return }
        finished = true
        headerTimer?.cancel()
        if dispatched && !responded {
            server.onDisconnect(id)
        }
        server.removeConnection(id)
    }
}
