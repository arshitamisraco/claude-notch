import Foundation
import os

@MainActor
final class CoreRuntime {
    let store: NotchStore

    private let settings: CoreSettings
    private let broker: DecisionBroker
    private let router: HookRouter
    private var server: HTTPServer?
    private var generation: Int = 0

    init(settings: CoreSettings) {
        let broker = DecisionBroker()
        self.settings = settings
        self.broker = broker
        let store = NotchStore(broker: broker)
        self.store = store
        self.router = HookRouter(store: store, broker: broker, settings: settings)
        broker.onTimeout = { (id: UUID) -> Void in
            Logger(subsystem: "dev.claudenotch", category: "broker").info("hold timed out: \(id.uuidString, privacy: .public)")
        }
    }

    /// Binds the listener; `store.serverState` follows the listener state.
    func start() {
        if server != nil { return }
        generation += 1
        let gen: Int = generation
        let port: UInt16 = settings.port
        let token: String = settings.authToken

        let handler: HTTPServer.Handler = { [weak self] (request: HTTPRequest, requestID: UUID) async -> HTTPResponse in
            guard let runtime = self else { return HTTPResponse.json(200, HookResponse.emptyData) }
            return await runtime.process(request: request, requestID: requestID)
        }
        let newServer = HTTPServer(
            port: port,
            token: token,
            handler: handler,
            onDisconnect: { [weak self] (requestID: UUID) in
                Task { @MainActor in
                    self?.router.clientDisconnected(requestID)
                }
            },
            onState: { [weak self] (state: ServerState) in
                Task { @MainActor in
                    guard let runtime = self, runtime.generation == gen else { return }
                    runtime.store.setServerState(state)
                }
            }
        )
        server = newServer
        newServer.start()
    }

    /// After a port/token change: releases held requests with `{}` and rebinds.
    func restart() {
        stopServer()
        store.releaseAllBlocking()
        store.setServerState(.stopped)
        start()
    }

    func shutdown() {
        store.releaseAllBlocking()
        stopServer()
        store.setServerState(.stopped)
    }

    private func stopServer() {
        generation += 1
        server?.stop()
        server = nil
    }

    private func process(request: HTTPRequest, requestID: UUID) async -> HTTPResponse {
        guard let endpoint = HookEndpoint(path: request.path) else {
            return HTTPResponse.error(404, "not found")
        }
        let payload: HookPayload
        do {
            payload = try JSONDecoder().decode(HookPayload.self, from: request.body)
        } catch {
            return HTTPResponse.error(400, "invalid hook payload")
        }
        let terminal: TerminalHint = RequestAuthenticator.terminalHint(from: request)
        let body: Data = await router.handle(endpoint: endpoint, payload: payload, terminal: terminal, requestID: requestID)
        return HTTPResponse.json(200, body)
    }
}
