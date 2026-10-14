import XCTest
@testable import ClaudeNotch

@MainActor
final class DecisionBrokerTests: XCTestCase {
    private func waitUntilHeld(_ broker: DecisionBroker, count: Int) async {
        var spins = 0
        while broker.heldCount < count && spins < 1000 {
            await Task.yield()
            spins += 1
        }
    }

    func testResolveReturnsDecision() async {
        let broker = DecisionBroker()
        let id = UUID()
        let task = Task { await broker.hold(id, timeout: 5) }
        await waitUntilHeld(broker, count: 1)
        XCTAssertTrue(broker.resolve(id, .approval(.allow)))
        let result = await task.value
        XCTAssertEqual(result, .approval(.allow))
        XCTAssertEqual(broker.heldCount, 0)
    }

    func testSecondResolveIsNoOp() async {
        let broker = DecisionBroker()
        let id = UUID()
        let task = Task { await broker.hold(id, timeout: 5) }
        await waitUntilHeld(broker, count: 1)
        XCTAssertTrue(broker.resolve(id, .answers(["q": "a"])))
        XCTAssertFalse(broker.resolve(id, .release))
        let result = await task.value
        XCTAssertEqual(result, .answers(["q": "a"]))
    }

    func testResolveUnknownReturnsFalse() {
        XCTAssertFalse(DecisionBroker().resolve(UUID(), .release))
    }

    func testTimeoutReleasesAndNotifies() async {
        let broker = DecisionBroker()
        let id = UUID()
        var timedOut: UUID? = nil
        broker.onTimeout = { timedOut = $0 }
        let result = await broker.hold(id, timeout: 0.05)
        XCTAssertEqual(result, .release)
        XCTAssertEqual(timedOut, id)
        XCTAssertEqual(broker.heldCount, 0)
    }

    func testReleaseAll() async {
        let broker = DecisionBroker()
        let a = UUID(), b = UUID()
        let ta = Task { await broker.hold(a, timeout: 5) }
        let tb = Task { await broker.hold(b, timeout: 5) }
        await waitUntilHeld(broker, count: 2)
        broker.releaseAll()
        let ra = await ta.value
        let rb = await tb.value
        XCTAssertEqual(ra, .release)
        XCTAssertEqual(rb, .release)
        XCTAssertEqual(broker.heldCount, 0)
    }

    func testResolveAfterTimeoutDoesNotDoubleResume() async {
        let broker = DecisionBroker()
        let id = UUID()
        let result = await broker.hold(id, timeout: 0.02)
        XCTAssertEqual(result, .release)
        XCTAssertFalse(broker.resolve(id, .approval(.allow)))
    }

    func testCancellationReleases() async {
        let broker = DecisionBroker()
        let id = UUID()
        let task = Task { await broker.hold(id, timeout: 30) }
        await waitUntilHeld(broker, count: 1)
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result, .release)
    }
}
