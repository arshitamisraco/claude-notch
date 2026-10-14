import SwiftUI
import AppKit
import Observation

enum NotchMode: Equatable {
    case idle, glance, peek, expanded
}

/// In-progress answers for a question item (multi-question stepper).
struct QuestionDraft: Equatable {
    var step: Int = 0
    var answers: [String: String] = [:]
    var selected: [String: [String]] = [:]
}

@MainActor @Observable
final class NotchViewModel {
    let store: NotchStore
    let settings: UISettings

    // Geometry / environment (set by the panel controller).
    var geometry: NotchGeometry = NotchGeometry.fallback
    var floating: Bool = false
    /// Interactive rect in root view coordinates (top-left origin), without slop.
    var interactiveRect: CGRect = .zero

    // Presentation state.
    var hoverExpanded: Bool = false
    var pinnedExpanded: Bool = false
    var peekItemID: NotchItem.ID?
    var peekTimedOut: Bool = false
    var selectedItemID: NotchItem.ID?
    var drafts: [UUID: QuestionDraft] = [:]
    var showCheck: Bool = false
    var forcedMode: NotchMode?

    // Hooks for the controller.
    @ObservationIgnored var onModeChange: ((NotchMode) -> Void)?
    @ObservationIgnored var onArrival: (() -> Void)?
    @ObservationIgnored var onInteractiveRectChange: (() -> Void)?
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
    @ObservationIgnored private var peekTask: Task<Void, Never>?
    @ObservationIgnored private var checkTask: Task<Void, Never>?

    init(store: NotchStore, settings: UISettings) {
        self.store = store
        self.settings = settings
    }

    // MARK: Derived layout

    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Effective notch size used for layout (floating pill has no camera cut-out).
    var layoutNotchWidth: CGFloat { floating ? 120 : geometry.notchWidth }
    var layoutNotchHeight: CGFloat { floating ? 28 : geometry.notchHeight }
    var fillet: CGFloat { floating ? 0 : Theme.Radius.fillet }

    // MARK: Mode

    var peekItem: NotchItem? {
        guard let id = peekItemID,
              let item = store.visibleItems.first(where: { $0.id == id }) else { return nil }
        if item.isBlocking && item.isPending { return item }
        if peekTimedOut { return nil }
        return item
    }

    var mode: NotchMode {
        if let forced = forcedMode { return forced }
        if hoverExpanded || pinnedExpanded { return .expanded }
        if peekItem != nil { return .peek }
        if store.hasActivity { return .glance }
        return .idle
    }

    // MARK: Items / pager

    var currentItem: NotchItem? {
        let items = store.visibleItems
        if let id = selectedItemID, let match = items.first(where: { $0.id == id }) { return match }
        return items.first
    }

    var pagerPosition: (index: Int, total: Int) {
        let items = store.visibleItems
        guard let current = currentItem, let idx = items.firstIndex(where: { $0.id == current.id }) else {
            return (0, items.count)
        }
        return (idx, items.count)
    }

    func nextItem() {
        let items = store.visibleItems
        let pos = pagerPosition
        guard pos.index + 1 < items.count else { return }
        selectedItemID = items[pos.index + 1].id
    }

    func previousItem() {
        let items = store.visibleItems
        let pos = pagerPosition
        guard pos.index - 1 >= 0, pos.index - 1 < items.count else { return }
        selectedItemID = items[pos.index - 1].id
    }

    // MARK: Arrivals

    func handleArrival() {
        guard let id = store.latestArrival,
              let item = store.visibleItems.first(where: { $0.id == id }) else { return }
        if case .done = item.kind {
            showCheck = true
            checkTask?.cancel()
            checkTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                self?.showCheck = false
            }
        }
        if item.isBlocking { selectedItemID = nil }
        onArrival?()
        guard settings.peekEnabled else { return }
        peekItemID = id
        peekTimedOut = false
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(NotchTiming.peekDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.peekTimedOut = true
        }
    }

    func modeDidChange() {
        onModeChange?(mode)
    }

    // MARK: Hover / expansion

    func pointerChanged(inside: Bool) {
        if inside {
            collapseTask?.cancel()
            collapseTask = nil
            if !hoverExpanded { hoverExpanded = true }
        } else if hoverExpanded && collapseTask == nil {
            collapseTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(NotchTiming.hoverCollapseGrace * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.hoverExpanded = false
                self?.collapseTask = nil
            }
        }
    }

    func togglePinned() {
        if mode == .expanded {
            collapse()
        } else {
            pinnedExpanded = true
        }
    }

    func collapse() {
        collapseTask?.cancel()
        collapseTask = nil
        hoverExpanded = false
        pinnedExpanded = false
    }

    // MARK: Actions

    func allow(_ item: NotchItem) { store.allow(item.id) }
    func allowAlways(_ item: NotchItem) { store.allowAlways(item.id) }
    func deny(_ item: NotchItem) { store.deny(item.id) }
    func handOff(_ item: NotchItem) { store.handOffToTerminal(item.id) }
    func dismiss(_ item: NotchItem) { store.dismiss(item.id) }
    func jump(to item: NotchItem) { store.jump(to: item.sessionID) }
    func jump(to session: SessionInfo) { store.jump(to: session.id) }

    // MARK: Questions

    func draft(for item: NotchItem) -> QuestionDraft {
        return drafts[item.id] ?? QuestionDraft()
    }

    func chooseOption(_ item: NotchItem, index: Int) {
        guard item.isPending, case .question(let req) = item.kind, !req.questions.isEmpty else { return }
        var d = draft(for: item)
        let step = min(d.step, req.questions.count - 1)
        let q = req.questions[step]
        guard index >= 0, index < q.options.count else { return }
        let label = q.options[index].label
        if q.multiSelect {
            var current = d.selected[q.question] ?? []
            if let pos = current.firstIndex(of: label) {
                current.remove(at: pos)
            } else {
                current.append(label)
            }
            d.selected[q.question] = current
            drafts[item.id] = d
        } else {
            d.answers[q.question] = label
            finishStep(item: item, request: req, draft: d)
        }
    }

    func submitMulti(_ item: NotchItem) {
        guard item.isPending, case .question(let req) = item.kind, !req.questions.isEmpty else { return }
        var d = draft(for: item)
        let step = min(d.step, req.questions.count - 1)
        let q = req.questions[step]
        guard q.multiSelect else { return }
        let picked = d.selected[q.question] ?? []
        guard !picked.isEmpty else { return }
        // Keep the order the options are shown in.
        let ordered = q.options.map { $0.label }.filter { picked.contains($0) }
        d.answers[q.question] = ordered.joined(separator: ", ")
        finishStep(item: item, request: req, draft: d)
    }

    private func finishStep(item: NotchItem, request: QuestionRequest, draft: QuestionDraft) {
        var d = draft
        if d.step + 1 >= request.questions.count {
            drafts[item.id] = d
            store.answer(item.id, answers: d.answers)
        } else {
            d.step += 1
            drafts[item.id] = d
        }
    }

    // MARK: Keyboard

    /// Returns true when the key was handled. Only called while expanded.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        let opt = flags.contains(.option)
        let ctrl = flags.contains(.control)
        let item = currentItem
        let pendingItem: NotchItem? = (item?.isPending ?? false) ? item : nil

        switch event.keyCode {
        case 53: // esc
            collapse()
            return true
        case 123: // left
            guard !cmd, !opt, !ctrl else { return false }
            previousItem()
            return true
        case 124: // right
            guard !cmd, !opt, !ctrl else { return false }
            nextItem()
            return true
        case 36, 76: // return / enter
            guard cmd, let p = pendingItem else { return false }
            switch p.kind {
            case .approval(let req):
                if opt {
                    if req.canAlwaysAllow { allowAlways(p) }
                } else {
                    allow(p)
                }
                return true
            case .question:
                if !opt { submitMulti(p) }
                return true
            default:
                return false
            }
        case 51: // delete
            guard cmd, let p = pendingItem, case .approval = p.kind else { return false }
            deny(p)
            return true
        default:
            break
        }

        if !cmd && !opt && !ctrl, let p = pendingItem, case .question = p.kind,
           let chars = event.charactersIgnoringModifiers, chars.count == 1,
           let n = Int(chars), n >= 1, n <= 4 {
            chooseOption(p, index: n - 1)
            return true
        }
        return false
    }
}

// MARK: - Presentation helpers

extension NotchItem {
    var uiStatus: SessionStatus { priority }

    var uiTitle: String {
        switch kind {
        case .approval(let req): return req.displayToolName
        case .question(let req): return req.questions.first?.header ?? "Claude asks"
        case .attention(let info): return info.title.isEmpty ? "Waiting for you" : info.title
        case .done: return "Finished"
        case .error(let info): return info.title.isEmpty ? "Error" : info.title
        }
    }

    /// One line shown in Peek.
    var uiHeadline: String {
        switch kind {
        case .approval(let req): return "\(req.headline) \(req.displayToolName)"
        case .question(let req): return req.questions.first?.question ?? "Claude asks"
        case .attention(let info): return info.title.isEmpty ? "Waiting for you" : info.title
        case .done: return "Finished"
        case .error(let info): return info.title.isEmpty ? "Error" : info.title
        }
    }

    var uiDetailLine: String? {
        switch kind {
        case .approval(let req): return req.summary
        case .question: return nil
        case .attention(let info): return info.message
        case .done(let info): return info.summary
        case .error(let info): return info.message
        }
    }
}
