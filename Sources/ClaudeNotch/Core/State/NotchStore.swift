import Foundation
import Observation

@MainActor @Observable
final class NotchStore {
    // MARK: read (UI)

    /// sorted: status desc, then lastEventAt desc
    private(set) var sessions: [SessionInfo] = []
    /// pending + lingering resolved + done/error/attention < 6s; pending first, priority desc, createdAt asc
    private(set) var visibleItems: [NotchItem] = []
    /// last 50 finished items, newest first
    private(set) var history: [NotchItem] = []
    /// changes on every newly created item (Peek trigger)
    private(set) var latestArrival: NotchItem.ID? = nil
    private(set) var serverState: ServerState = .stopped

    var pendingItems: [NotchItem] {
        return visibleItems.filter { $0.isBlocking && $0.isPending }
    }

    var aggregateStatus: SessionStatus {
        var best: SessionStatus = .idle
        for s in sessions where s.status > best { best = s.status }
        for i in visibleItems where i.isPending && i.priority > best { best = i.priority }
        return best
    }

    var hasActivity: Bool {
        if !visibleItems.isEmpty { return true }
        return sessions.contains { $0.status != .idle }
    }

    func session(_ id: SessionID) -> SessionInfo? {
        return sessions.first { $0.id == id }
    }

    // MARK: integration

    @ObservationIgnored var terminalFocuser: (@MainActor (SessionInfo) -> Void)?

    func addArrivalObserver(_ observer: @escaping @MainActor (NotchItem) -> Void) {
        arrivalObservers.append(observer)
    }

    // MARK: internals

    static let historyLimit: Int = 50
    static let sessionReapDelay: TimeInterval = 10
    static let sessionIdleTimeout: TimeInterval = 30 * 60
    static let recentWindow: TimeInterval = 5

    private let broker: DecisionBroker
    @ObservationIgnored private var baseSessions: [SessionID: SessionInfo] = [:]
    @ObservationIgnored private var allItems: [NotchItem] = []
    @ObservationIgnored private var toolUseIDs: [UUID: String] = [:]
    @ObservationIgnored private var itemTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var reapTasks: [SessionID: Task<Void, Never>] = [:]
    @ObservationIgnored private var sweepTask: Task<Void, Never>?
    @ObservationIgnored private var arrivalObservers: [@MainActor (NotchItem) -> Void] = []
    @ObservationIgnored private var isPreview: Bool = false

    init() {
        self.broker = DecisionBroker()
    }

    init(broker: DecisionBroker) {
        self.broker = broker
    }

    /// Static store for UI previews: no server, no timers, items never expire.
    static func preview(sessions: [SessionInfo], items: [NotchItem]) -> NotchStore {
        let store = NotchStore()
        store.isPreview = true
        for s in sessions { store.baseSessions[s.id] = s }
        store.allItems = items
        store.refresh()
        return store
    }

    // MARK: actions (UI -> Core)

    func allow(_ id: NotchItem.ID) {
        guard let item = pendingBlocking(id), case .approval = item.kind else { return }
        broker.resolve(id, .approval(.allow))
        resolveItem(id, .allowed)
    }

    func allowAlways(_ id: NotchItem.ID) {
        guard let item = pendingBlocking(id), case .approval(let request) = item.kind else { return }
        if !request.canAlwaysAllow {
            allow(id)
            return
        }
        broker.resolve(id, .approval(.allowAlways))
        resolveItem(id, .alwaysAllowed)
    }

    func deny(_ id: NotchItem.ID, message: String? = nil) {
        guard let item = pendingBlocking(id), case .approval = item.kind else { return }
        let text: String = (message?.isEmpty == false) ? (message ?? HookResponse.defaultDenyMessage) : HookResponse.defaultDenyMessage
        broker.resolve(id, .approval(.deny(message: text)))
        resolveItem(id, .denied)
    }

    func answer(_ id: NotchItem.ID, answers: QuestionAnswers) {
        guard let item = pendingBlocking(id), case .question = item.kind else { return }
        broker.resolve(id, .answers(answers))
        resolveItem(id, .answered)
    }

    func handOffToTerminal(_ id: NotchItem.ID) {
        guard let item = pendingBlocking(id) else { return }
        broker.resolve(id, .release)
        resolveItem(id, .handedOff)
        jump(to: item.sessionID)
    }

    func dismiss(_ id: NotchItem.ID) {
        guard let item = allItems.first(where: { $0.id == id }), !item.isBlocking, item.isPending else { return }
        resolveItem(id, .dismissed)
    }

    func jump(to sessionID: SessionID) {
        guard let focuser = terminalFocuser, let info = session(sessionID) else { return }
        focuser(info)
    }

    // MARK: Core-internal mutation (used by HookRouter / CoreRuntime)

    func setServerState(_ state: ServerState) {
        serverState = state
    }

    /// Reduces the event into the session table (creating it lazily).
    @discardableResult
    func applyEvent(_ payload: HookPayload, terminal: TerminalHint, now: Date = Date()) -> SessionInfo {
        let updated: SessionInfo = SessionReducer.reduce(baseSessions[payload.sessionId], payload: payload, terminal: terminal, now: now)
        baseSessions[payload.sessionId] = updated
        let sid: SessionID = payload.sessionId
        reapTasks[sid]?.cancel()
        reapTasks[sid] = nil
        if payload.event == .sessionEnd {
            reapTasks[sid] = scheduleTask(after: NotchStore.sessionReapDelay) { [weak self] in
                self?.removeSession(sid)
            }
        }
        ensureSweeper()
        refresh()
        return session(sid) ?? updated
    }

    /// Releases every pending blocking item that `payload` supersedes (PLAN §3 release table).
    func releaseMatching(_ payload: HookPayload) {
        let candidates: [NotchItem] = allItems.filter { item in
            SessionReducer.shouldRelease(item: item, itemToolUseID: toolUseIDs[item.id], by: payload)
        }
        for item in candidates {
            broker.resolve(item.id, .release)
            resolveItem(item.id, .answeredInTerminal)
        }
    }

    func append(_ item: NotchItem, toolUseID: String? = nil) {
        allItems.append(item)
        if let t = toolUseID { toolUseIDs[item.id] = t }
        latestArrival = item.id
        if !item.isBlocking && !isPreview {
            let id: UUID = item.id
            itemTasks[id] = scheduleTask(after: NotchTiming.doneLifetime) { [weak self] in
                self?.expireItem(id)
            }
        }
        refresh()
        for observer in arrivalObservers { observer(item) }
    }

    /// Idempotent: no-op unless the item is currently pending.
    func resolveItem(_ id: UUID, _ resolution: Resolution, now: Date = Date()) {
        guard let index = allItems.firstIndex(where: { $0.id == id }), allItems[index].isPending else { return }
        allItems[index].state = .resolved(resolution, at: now)
        itemTasks[id]?.cancel()
        itemTasks[id] = nil
        if allItems[index].isBlocking && !isPreview {
            itemTasks[id] = scheduleTask(after: NotchTiming.resolvedLinger) { [weak self] in
                self?.moveToHistory(id)
            }
            refresh()
        } else {
            moveToHistory(id)
        }
    }

    func pendingBlockingItem(withID id: UUID) -> NotchItem? {
        return pendingBlocking(id)
    }

    func hasPendingApproval(sessionID: SessionID, fingerprint: String) -> Bool {
        for item in allItems where item.isPending && item.sessionID == sessionID {
            if case .approval(let request) = item.kind {
                if ToolSummarizer.fingerprint(toolName: request.toolName, toolInput: request.toolInput) == fingerprint {
                    return true
                }
            }
        }
        return false
    }

    enum BlockingKind { case approval, question }

    /// True if the session has a pending item of `kind`, or one resolved within `window` seconds.
    func hasRecentBlockingItem(sessionID: SessionID, kind: BlockingKind, within window: TimeInterval = NotchStore.recentWindow, now: Date = Date()) -> Bool {
        func matches(_ item: NotchItem) -> Bool {
            guard item.sessionID == sessionID else { return false }
            switch (item.kind, kind) {
            case (.approval, .approval), (.question, .question): break
            default: return false
            }
            switch item.state {
            case .pending: return true
            case .resolved(_, let at): return now.timeIntervalSince(at) <= window
            }
        }
        return allItems.contains(where: matches) || history.contains(where: matches)
    }

    /// Releases everything still held and resolves blocking items (shutdown / restart).
    func releaseAllBlocking() {
        broker.releaseAll()
        let ids: [UUID] = allItems.filter { $0.isBlocking && $0.isPending }.map { $0.id }
        for id in ids { resolveItem(id, .answeredInTerminal) }
    }

    /// Drops idle/done sessions with no events for 30 minutes.
    func sweep(now: Date = Date()) {
        let hasPending: Set<SessionID> = Set(allItems.filter { $0.isPending }.map { $0.sessionID })
        var removed: Bool = false
        for (id, s) in baseSessions {
            guard s.status == .idle || s.status == .done else { continue }
            if hasPending.contains(id) { continue }
            if now.timeIntervalSince(s.lastEventAt) > NotchStore.sessionIdleTimeout {
                baseSessions[id] = nil
                reapTasks[id]?.cancel()
                reapTasks[id] = nil
                removed = true
            }
        }
        if removed { refresh() }
    }

    func removeSession(_ id: SessionID) {
        baseSessions[id] = nil
        reapTasks[id]?.cancel()
        reapTasks[id] = nil
        refresh()
    }

    // MARK: private

    private func pendingBlocking(_ id: UUID) -> NotchItem? {
        guard let item = allItems.first(where: { $0.id == id }), item.isBlocking, item.isPending else { return nil }
        return item
    }

    private func expireItem(_ id: UUID) {
        guard let index = allItems.firstIndex(where: { $0.id == id }) else { return }
        if allItems[index].isPending {
            allItems[index].state = .resolved(.expired, at: Date())
        }
        moveToHistory(id)
    }

    private func moveToHistory(_ id: UUID) {
        itemTasks[id]?.cancel()
        itemTasks[id] = nil
        toolUseIDs[id] = nil
        guard let index = allItems.firstIndex(where: { $0.id == id }) else { return }
        let item: NotchItem = allItems.remove(at: index)
        history.insert(item, at: 0)
        if history.count > NotchStore.historyLimit {
            history.removeLast(history.count - NotchStore.historyLimit)
        }
        refresh()
    }

    private func scheduleTask(after seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        let nanos: UInt64 = UInt64(max(0.0, seconds) * 1_000_000_000)
        return Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled { return }
            work()
        }
    }

    private func ensureSweeper() {
        if sweepTask != nil || isPreview { return }
        sweepTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { return }
                guard let store = self else { return }
                store.sweep()
            }
        }
    }

    /// Rebuilds the published, derived arrays.
    private func refresh() {
        var blockingCounts: [SessionID: Int] = [:]
        var topPending: [SessionID: SessionStatus] = [:]
        for item in allItems where item.isPending {
            if item.isBlocking { blockingCounts[item.sessionID, default: 0] += 1 }
            let current: SessionStatus = topPending[item.sessionID] ?? .idle
            if item.priority > current { topPending[item.sessionID] = item.priority }
        }
        var list: [SessionInfo] = []
        for (id, base) in baseSessions {
            var s: SessionInfo = base
            s.pendingItemCount = blockingCounts[id] ?? 0
            if let top = topPending[id], top > s.status { s.status = top }
            list.append(s)
        }
        list.sort { (a: SessionInfo, b: SessionInfo) -> Bool in
            if a.status != b.status { return a.status > b.status }
            return a.lastEventAt > b.lastEventAt
        }
        sessions = list

        visibleItems = allItems.sorted { (a: NotchItem, b: NotchItem) -> Bool in
            if a.isPending != b.isPending { return a.isPending }
            if a.priority != b.priority { return a.priority > b.priority }
            return a.createdAt < b.createdAt
        }
    }
}
