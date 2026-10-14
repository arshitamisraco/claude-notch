import XCTest
@testable import ClaudeNotch

@MainActor
final class StubCoreSettings: CoreSettings {
    var port: UInt16 = 41817
    var authToken: String = "secret-token"
    var holdTimeout: TimeInterval = 110
    var showToolFailures: Bool = false
}

final class SessionReducerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func event(_ name: String, _ configure: (inout HookPayload) -> Void = { _ in }) -> HookPayload {
        var p = HookPayload(sessionId: "sess-1", hookEventName: name, cwd: "/Users/me/my-project")
        configure(&p)
        return p
    }

    func testLazyCreationAndProjectName() {
        let s = SessionReducer.reduce(nil, payload: event("UserPromptSubmit"), now: t0)
        XCTAssertEqual(s.id, "sess-1")
        XCTAssertEqual(s.projectName, "my-project")
        XCTAssertEqual(s.status, .working)
        XCTAssertEqual(s.activity, "Thinking")
        XCTAssertEqual(s.startedAt, t0)
    }

    func testMissingCwdIsClaude() {
        let p = HookPayload(sessionId: "x", hookEventName: "SessionStart")
        XCTAssertEqual(SessionReducer.reduce(nil, payload: p, now: t0).projectName, "Claude")
    }

    func testToolLifecycle() {
        var s = SessionReducer.reduce(nil, payload: event("UserPromptSubmit"), now: t0)
        let t1 = t0.addingTimeInterval(5)
        s = SessionReducer.reduce(s, payload: event("PreToolUse") { $0.toolName = "Bash" }, now: t1)
        XCTAssertEqual(s.activity, "Running Bash")
        XCTAssertEqual(s.activityStartedAt, t1)
        let t2 = t0.addingTimeInterval(9)
        s = SessionReducer.reduce(s, payload: event("PostToolUseFailure") { $0.toolName = "Bash" }, now: t2)
        XCTAssertEqual(s.activity, "Bash failed")
        s = SessionReducer.reduce(s, payload: event("Stop"), now: t2.addingTimeInterval(1))
        XCTAssertEqual(s.status, .done)
        XCTAssertEqual(s.activity, "Finished")
    }

    func testStopHookActiveIgnored() {
        var s = SessionReducer.reduce(nil, payload: event("UserPromptSubmit"), now: t0)
        s = SessionReducer.reduce(s, payload: event("Stop") { $0.stopHookActive = true }, now: t0.addingTimeInterval(1))
        XCTAssertEqual(s.status, .working)
    }

    func testIdlePromptSetsAttention() {
        let s = SessionReducer.reduce(nil, payload: event("Notification") { $0.notificationType = "idle_prompt" }, now: t0)
        XCTAssertEqual(s.status, .attention)
        XCTAssertEqual(s.activity, "Waiting for you")
    }

    func testPermissionPromptNotificationDoesNotChangeStatus() {
        var s = SessionReducer.reduce(nil, payload: event("UserPromptSubmit"), now: t0)
        s = SessionReducer.reduce(s, payload: event("Notification") { $0.notificationType = "permission_prompt" }, now: t0)
        XCTAssertEqual(s.status, .working)
    }

    func testSessionEndAndTerminalMerge() {
        var s = SessionReducer.reduce(nil, payload: event("SessionStart"), terminal: TerminalHint(bundleID: "b", termProgram: nil), now: t0)
        s = SessionReducer.reduce(s, payload: event("UserPromptSubmit"), terminal: TerminalHint(bundleID: nil, termProgram: "iTerm.app"), now: t0)
        XCTAssertEqual(s.terminal.bundleID, "b")
        XCTAssertEqual(s.terminal.termProgram, "iTerm.app")
        s = SessionReducer.reduce(s, payload: event("SessionEnd"), now: t0)
        XCTAssertEqual(s.status, .idle)
        XCTAssertNil(s.activity)
    }

    // MARK: release rules

    private func approvalItem(session: String = "sess-1", tool: String = "Bash", input: JSONValue) -> NotchItem {
        let req = ApprovalRequest(toolName: tool, displayToolName: tool, headline: "Claude wants to run", summary: "s", detail: nil, toolInput: input, suggestions: [])
        return NotchItem(id: UUID(), sessionID: session, projectName: "p", cwd: "/p", createdAt: t0, kind: .approval(req), state: .pending)
    }

    private func questionItem() -> NotchItem {
        let q = QuestionRequest(questions: [QuestionPrompt(question: "Q?", header: nil, options: [QuestionOption(label: "A", description: nil)], multiSelect: false)])
        return NotchItem(id: UUID(), sessionID: "sess-1", projectName: "p", cwd: "/p", createdAt: t0, kind: .question(q), state: .pending)
    }

    func testApprovalReleasedByMatchingPostToolUse() {
        let input: JSONValue = .object(["command": .string("ls")])
        let item = approvalItem(input: input)
        let match = event("PostToolUse") { $0.toolName = "Bash"; $0.toolInput = input }
        XCTAssertTrue(SessionReducer.shouldRelease(item: item, itemToolUseID: nil, by: match))
        let otherInput = event("PostToolUse") { $0.toolName = "Bash"; $0.toolInput = .object(["command": .string("pwd")]) }
        XCTAssertFalse(SessionReducer.shouldRelease(item: item, itemToolUseID: nil, by: otherInput))
        let otherTool = event("PostToolUse") { $0.toolName = "Edit"; $0.toolInput = input }
        XCTAssertFalse(SessionReducer.shouldRelease(item: item, itemToolUseID: nil, by: otherTool))
    }

    func testToolUseIDTakesPrecedence() {
        let item = approvalItem(input: .object(["command": .string("ls")]))
        let same = event("PostToolUse") { $0.toolName = "Other"; $0.toolUseId = "t1" }
        XCTAssertTrue(SessionReducer.shouldRelease(item: item, itemToolUseID: "t1", by: same))
        let different = event("PostToolUse") { $0.toolName = "Bash"; $0.toolInput = .object(["command": .string("ls")]); $0.toolUseId = "t2" }
        XCTAssertFalse(SessionReducer.shouldRelease(item: item, itemToolUseID: "t1", by: different))
    }

    func testPromptStopAndEndReleaseBlocking() {
        let a = approvalItem(input: .object([:]))
        let q = questionItem()
        for name in ["UserPromptSubmit", "Stop", "SessionEnd"] {
            XCTAssertTrue(SessionReducer.shouldRelease(item: a, itemToolUseID: nil, by: event(name)), name)
            XCTAssertTrue(SessionReducer.shouldRelease(item: q, itemToolUseID: nil, by: event(name)), name)
        }
    }

    func testUnrelatedPreToolUseDoesNotRelease() {
        let a = approvalItem(input: .object([:]))
        XCTAssertFalse(SessionReducer.shouldRelease(item: a, itemToolUseID: nil, by: event("PreToolUse") { $0.toolName = "Bash" }))
        XCTAssertFalse(SessionReducer.shouldRelease(item: a, itemToolUseID: nil, by: event("Notification")))
    }

    func testOtherSessionDoesNotRelease() {
        let a = approvalItem(session: "other", input: .object([:]))
        XCTAssertFalse(SessionReducer.shouldRelease(item: a, itemToolUseID: nil, by: event("UserPromptSubmit")))
    }

    func testQuestionReleasedByAskUserQuestionPostToolUse() {
        let q = questionItem()
        XCTAssertTrue(SessionReducer.shouldRelease(item: q, itemToolUseID: nil, by: event("PostToolUse") { $0.toolName = "AskUserQuestion" }))
        XCTAssertFalse(SessionReducer.shouldRelease(item: q, itemToolUseID: nil, by: event("PostToolUse") { $0.toolName = "Bash" }))
    }

    func testResolvedItemNotReleased() {
        var a = approvalItem(input: .object([:]))
        a.state = .resolved(.allowed, at: t0)
        XCTAssertFalse(SessionReducer.shouldRelease(item: a, itemToolUseID: nil, by: event("Stop")))
    }
}

// MARK: store + router

@MainActor
final class NotchStoreRouterTests: XCTestCase {
    private var settings: StubCoreSettings!
    private var broker: DecisionBroker!
    private var store: NotchStore!
    private var router: HookRouter!

    override func setUp() {
        super.setUp()
        settings = StubCoreSettings()
        broker = DecisionBroker()
        store = NotchStore(broker: broker)
        router = HookRouter(store: store, broker: broker, settings: settings)
    }

    private func payload(_ name: String, _ configure: (inout HookPayload) -> Void = { _ in }) -> HookPayload {
        var p = HookPayload(sessionId: "s1", hookEventName: name, cwd: "/tmp/proj")
        configure(&p)
        return p
    }

    private func waitForPending(_ count: Int) async {
        var spins = 0
        while store.pendingItems.count < count && spins < 1000 {
            await Task.yield()
            spins += 1
        }
    }

    func testApprovalAllowFlow() async {
        let id = UUID()
        let p = payload("PermissionRequest") { $0.toolName = "Bash"; $0.toolInput = .object(["command": .string("ls")]) }
        let task = Task { await self.router.handle(endpoint: .hook, payload: p, terminal: .unknown, requestID: id) }
        await waitForPending(1)
        XCTAssertEqual(store.pendingItems.count, 1)
        XCTAssertEqual(store.session("s1")?.status, .approval)
        XCTAssertEqual(store.session("s1")?.pendingItemCount, 1)
        XCTAssertEqual(store.aggregateStatus, .approval)
        XCTAssertEqual(store.latestArrival, id)
        store.allow(id)
        let data = await task.value
        XCTAssertEqual(String(data: data, encoding: .utf8), HookResponse.string(HookResponse.allow()))
        XCTAssertTrue(store.pendingItems.isEmpty)
        if case .resolved(let res, _)? = store.visibleItems.first?.state { XCTAssertEqual(res, .allowed) } else { XCTFail("expected lingering resolved item") }
        store.allow(id) // idempotent
    }

    func testDenyAndAllowAlwaysFallback() async {
        let id = UUID()
        let p = payload("PermissionRequest") { $0.toolName = "Bash"; $0.toolInput = .object(["command": .string("rm x")]) }
        let task = Task { await self.router.handle(endpoint: .hook, payload: p, terminal: .unknown, requestID: id) }
        await waitForPending(1)
        store.deny(id)
        let data = await task.value
        XCTAssertEqual(String(data: data, encoding: .utf8), HookResponse.string(HookResponse.deny(message: nil)))

        // allowAlways without suggestions falls back to allow
        let id2 = UUID()
        let p2 = payload("PermissionRequest") { $0.toolName = "Bash"; $0.toolInput = .object(["command": .string("ls")]) }
        let task2 = Task { await self.router.handle(endpoint: .hook, payload: p2, terminal: .unknown, requestID: id2) }
        await waitForPending(1)
        store.allowAlways(id2)
        let data2 = await task2.value
        XCTAssertEqual(String(data: data2, encoding: .utf8), HookResponse.string(HookResponse.allow()))
    }

    func testDuplicateApprovalGetsEmptyImmediately() async {
        let input: JSONValue = .object(["command": .string("ls")])
        let id = UUID()
        let p = payload("PermissionRequest") { $0.toolName = "Bash"; $0.toolInput = input }
        let task = Task { await self.router.handle(endpoint: .hook, payload: p, terminal: .unknown, requestID: id) }
        await waitForPending(1)
        let dup = await router.handle(endpoint: .hook, payload: p, terminal: .unknown, requestID: UUID())
        XCTAssertEqual(dup, HookResponse.emptyData)
        XCTAssertEqual(store.pendingItems.count, 1)
        store.handOffToTerminal(id)
        let first = await task.value
        XCTAssertEqual(first, HookResponse.emptyData)
    }

    func testPostToolUseReleasesPendingApproval() async {
        let input: JSONValue = .object(["command": .string("ls")])
        let id = UUID()
        let p = payload("PermissionRequest") { $0.toolName = "Bash"; $0.toolInput = input }
        let task = Task { await self.router.handle(endpoint: .hook, payload: p, terminal: .unknown, requestID: id) }
        await waitForPending(1)
        _ = await router.handle(endpoint: .event, payload: payload("PostToolUse") { $0.toolName = "Bash"; $0.toolInput = input }, terminal: .unknown, requestID: UUID())
        let data = await task.value
        XCTAssertEqual(data, HookResponse.emptyData)
        if case .resolved(let res, _)? = store.visibleItems.first?.state { XCTAssertEqual(res, .answeredInTerminal) } else { XCTFail("expected resolved item") }
    }

    func testClientDisconnectReleases() async {
        let id = UUID()
        let p = payload("PermissionRequest") { $0.toolName = "Bash"; $0.toolInput = .object(["command": .string("ls")]) }
        let task = Task { await self.router.handle(endpoint: .hook, payload: p, terminal: .unknown, requestID: id) }
        await waitForPending(1)
        router.clientDisconnected(id)
        let data = await task.value
        XCTAssertEqual(data, HookResponse.emptyData)
        XCTAssertTrue(store.pendingItems.isEmpty)
    }

    func testQuestionAnswerFlow() async {
        let input: JSONValue = .object(["questions": .array([
            .object(["question": .string("Which?"), "options": .array([.object(["label": .string("A")]), .object(["label": .string("B")])])])
        ])])
        let id = UUID()
        let p = payload("PreToolUse") { $0.toolName = "AskUserQuestion"; $0.toolInput = input }
        let task = Task { await self.router.handle(endpoint: .hook, payload: p, terminal: .unknown, requestID: id) }
        await waitForPending(1)
        XCTAssertEqual(store.session("s1")?.status, .question)
        store.answer(id, answers: ["Which?": "B"])
        let data = await task.value
        XCTAssertEqual(String(data: data, encoding: .utf8), HookResponse.string(HookResponse.answer(toolInput: input, answers: ["Which?": "B"])))
    }

    func testMalformedQuestionReturnsEmptyAndShowsNothing() async {
        let p = payload("PreToolUse") { $0.toolName = "AskUserQuestion"; $0.toolInput = .object(["questions": .array([])]) }
        let data = await router.handle(endpoint: .hook, payload: p, terminal: .unknown, requestID: UUID())
        XCTAssertEqual(data, HookResponse.emptyData)
        XCTAssertTrue(store.visibleItems.isEmpty)
    }

    func testEventEndpointNeverHolds() async {
        let p = payload("PermissionRequest") { $0.toolName = "Bash"; $0.toolInput = .object([:]) }
        let data = await router.handle(endpoint: .event, payload: p, terminal: .unknown, requestID: UUID())
        XCTAssertEqual(data, HookResponse.emptyData)
        XCTAssertTrue(store.visibleItems.isEmpty)
    }

    func testStopCreatesDoneItemOncePerTurnAndIgnoresStopHookActive() async {
        _ = await router.handle(endpoint: .event, payload: payload("Stop") { $0.lastAssistantMessage = "\nAll done.\nBye" }, terminal: .unknown, requestID: UUID())
        XCTAssertEqual(store.visibleItems.count, 1)
        if case .done(let info) = store.visibleItems[0].kind { XCTAssertEqual(info.summary, "All done.") } else { XCTFail("expected done") }
        _ = await router.handle(endpoint: .event, payload: payload("Stop") { $0.stopHookActive = true }, terminal: .unknown, requestID: UUID())
        XCTAssertEqual(store.visibleItems.count, 1)
        let item = store.visibleItems[0]
        store.dismiss(item.id)
        XCTAssertTrue(store.visibleItems.isEmpty)
        XCTAssertEqual(store.history.first?.id, item.id)
    }

    func testPermissionPromptNotificationDedupe() async {
        // No pending approval -> attention item
        _ = await router.handle(endpoint: .event, payload: payload("Notification") { $0.notificationType = "permission_prompt" }, terminal: .unknown, requestID: UUID())
        XCTAssertEqual(store.visibleItems.count, 1)
        if case .attention(let info) = store.visibleItems[0].kind { XCTAssertEqual(info.message, "Approve in terminal") } else { XCTFail("expected attention") }

        // Pending approval -> dropped
        let id = UUID()
        let p = payload("PermissionRequest") { $0.toolName = "Bash"; $0.toolInput = .object(["command": .string("ls")]) }
        let task = Task { await self.router.handle(endpoint: .hook, payload: p, terminal: .unknown, requestID: id) }
        await waitForPending(1)
        let before = store.visibleItems.count
        _ = await router.handle(endpoint: .event, payload: payload("Notification") { $0.notificationType = "permission_prompt" }, terminal: .unknown, requestID: UUID())
        XCTAssertEqual(store.visibleItems.count, before)
        store.deny(id)
        _ = await task.value
        // Recently resolved (within 5s) -> still dropped
        _ = await router.handle(endpoint: .event, payload: payload("Notification") { $0.notificationType = "permission_prompt" }, terminal: .unknown, requestID: UUID())
        XCTAssertEqual(store.visibleItems.count, before)
    }

    func testIdlePromptOnlySetsSessionAttention() async {
        _ = await router.handle(endpoint: .event, payload: payload("Notification") { $0.notificationType = "idle_prompt" }, terminal: .unknown, requestID: UUID())
        XCTAssertTrue(store.visibleItems.isEmpty)
        XCTAssertEqual(store.session("s1")?.status, .attention)
        XCTAssertTrue(store.hasActivity)
    }

    func testToolFailureItemOnlyWhenEnabled() async {
        let fail = payload("PostToolUseFailure") { $0.toolName = "Bash"; $0.error = "exit 1" }
        _ = await router.handle(endpoint: .event, payload: fail, terminal: .unknown, requestID: UUID())
        XCTAssertTrue(store.visibleItems.isEmpty)
        XCTAssertEqual(store.session("s1")?.activity, "Bash failed")
        settings.showToolFailures = true
        _ = await router.handle(endpoint: .event, payload: fail, terminal: .unknown, requestID: UUID())
        XCTAssertEqual(store.visibleItems.count, 1)
    }

    func testReleaseAllBlocking() async {
        let id = UUID()
        let p = payload("PermissionRequest") { $0.toolName = "Bash"; $0.toolInput = .object(["command": .string("ls")]) }
        let task = Task { await self.router.handle(endpoint: .hook, payload: p, terminal: .unknown, requestID: id) }
        await waitForPending(1)
        store.releaseAllBlocking()
        let data = await task.value
        XCTAssertEqual(data, HookResponse.emptyData)
        XCTAssertTrue(store.pendingItems.isEmpty)
    }

    func testSweepRemovesStaleIdleSessions() async {
        _ = await router.handle(endpoint: .event, payload: payload("SessionStart"), terminal: .unknown, requestID: UUID())
        XCTAssertNotNil(store.session("s1"))
        store.sweep(now: Date().addingTimeInterval(31 * 60))
        XCTAssertNil(store.session("s1"))
    }

    func testPreviewStore() {
        let session = SessionInfo(id: "p", cwd: "/x", projectName: "x", status: .working, activity: nil, activityStartedAt: Date(), startedAt: Date(), lastEventAt: Date(), pendingItemCount: 0, permissionMode: nil, terminal: .unknown)
        let req = ApprovalRequest(toolName: "Bash", displayToolName: "Bash", headline: "Claude wants to run", summary: "ls", detail: nil, toolInput: .object([:]), suggestions: [])
        let item = NotchItem(id: UUID(), sessionID: "p", projectName: "x", cwd: "/x", createdAt: Date(), kind: .approval(req), state: .pending)
        let preview = NotchStore.preview(sessions: [session], items: [item])
        XCTAssertEqual(preview.pendingItems.count, 1)
        XCTAssertEqual(preview.session("p")?.status, .approval)
        XCTAssertEqual(preview.session("p")?.pendingItemCount, 1)
    }
}
