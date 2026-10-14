import Foundation

enum HookDecision: Equatable, Sendable {
    case release
    case approval(ApprovalDecision)
    case answers(QuestionAnswers)
}

/// Holds one CheckedContinuation per held request and guarantees it is resumed exactly once.
@MainActor
final class DecisionBroker {
    private var continuations: [UUID: CheckedContinuation<HookDecision, Never>] = [:]
    private var timeoutTasks: [UUID: Task<Void, Never>] = [:]

    /// Called (after the continuation has been released) when a hold times out.
    var onTimeout: ((UUID) -> Void)?

    var heldCount: Int { return continuations.count }

    func isHolding(_ id: UUID) -> Bool {
        return continuations[id] != nil
    }

    /// Suspends until resolved. Returns `.release` on timeout / cancel / releaseAll.
    func hold(_ id: UUID, timeout: TimeInterval) async -> HookDecision {
        if Task.isCancelled { return .release }
        // A second hold for the same id releases the first so nothing leaks.
        if continuations[id] != nil {
            _ = resolve(id, .release)
        }
        return await withTaskCancellationHandler(
            operation: { () -> HookDecision in
                return await withCheckedContinuation { (continuation: CheckedContinuation<HookDecision, Never>) in
                    self.continuations[id] = continuation
                    let nanos: UInt64 = UInt64(max(0.0, timeout) * 1_000_000_000)
                    self.timeoutTasks[id] = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: nanos)
                        if Task.isCancelled { return }
                        self?.timeoutFired(id)
                    }
                }
            },
            onCancel: {
                Task { @MainActor [weak self] in
                    _ = self?.resolve(id, .release)
                }
            }
        )
    }

    /// Returns true if a held request was resumed.
    @discardableResult
    func resolve(_ id: UUID, _ decision: HookDecision) -> Bool {
        guard let continuation = continuations.removeValue(forKey: id) else { return false }
        if let task = timeoutTasks.removeValue(forKey: id) { task.cancel() }
        continuation.resume(returning: decision)
        return true
    }

    func releaseAll() {
        let ids: [UUID] = Array(continuations.keys)
        for id in ids {
            _ = resolve(id, .release)
        }
    }

    private func timeoutFired(_ id: UUID) {
        if resolve(id, .release) {
            onTimeout?(id)
        }
    }
}
