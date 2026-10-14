import Foundation
import os

enum HookEndpoint: Equatable, Sendable {
    case hook    // may hold
    case event   // observe only

    init?(path: String) {
        switch path {
        case RequestAuthenticator.hookPath: self = .hook
        case RequestAuthenticator.eventPath: self = .event
        default: return nil
        }
    }
}

/// Dispatches decoded hook payloads: observe vs hold, dedupe, HookDecision -> response body.
@MainActor
final class HookRouter {
    static let maxHeldRequests: Int = 32

    private let store: NotchStore
    private let broker: DecisionBroker
    private let settings: CoreSettings
    private let log = Logger(subsystem: "dev.claudenotch", category: "router")

    init(store: NotchStore, broker: DecisionBroker, settings: CoreSettings) {
        self.store = store
        self.broker = broker
        self.settings = settings
    }

    /// `requestID` doubles as the NotchItem id for held requests.
    func handle(endpoint: HookEndpoint, payload: HookPayload, terminal: TerminalHint, requestID: UUID, now: Date = Date()) async -> Data {
        let session: SessionInfo = store.applyEvent(payload, terminal: terminal, now: now)
        store.releaseMatching(payload)

        switch payload.event {
        case .permissionRequest:
            if endpoint == .hook {
                return await holdApproval(payload: payload, session: session, requestID: requestID, now: now)
            }
        case .preToolUse:
            if endpoint == .hook && payload.toolName == "AskUserQuestion" {
                return await holdQuestion(payload: payload, session: session, requestID: requestID, now: now)
            }
        case .notification:
            handleNotification(payload: payload, session: session, now: now)
        case .stop:
            if payload.stopHookActive != true {
                let info = DoneInfo(summary: payload.lastAssistantMessage.flatMap { ToolSummarizer.firstLine($0) })
                store.append(makeItem(id: UUID(), session: session, kind: .done(info), now: now))
            }
        case .postToolUseFailure:
            if settings.showToolFailures && payload.isInterrupt != true {
                let name: String = ToolSummarizer.displayName(for: payload.toolName ?? "Tool")
                let message: String = payload.error.flatMap { ToolSummarizer.firstLine($0) } ?? "The tool call failed"
                let info = ErrorInfo(title: "\(name) failed", message: ToolSummarizer.truncate(message, limit: 300))
                store.append(makeItem(id: UUID(), session: session, kind: .error(info), now: now))
            }
        default:
            break
        }
        return HookResponse.emptyData
    }

    /// HTTP client went away before we answered.
    func clientDisconnected(_ requestID: UUID) {
        broker.resolve(requestID, .release)
    }

    // MARK: held flows

    private func holdApproval(payload: HookPayload, session: SessionInfo, requestID: UUID, now: Date) async -> Data {
        let toolName: String = payload.toolName ?? "Unknown"
        let toolInput: JSONValue = payload.toolInput ?? .object([:])
        let fingerprint: String = ToolSummarizer.fingerprint(toolName: toolName, toolInput: toolInput)
        if store.hasPendingApproval(sessionID: session.id, fingerprint: fingerprint) { return HookResponse.emptyData }
        if broker.heldCount >= HookRouter.maxHeldRequests { return HookResponse.emptyData }

        let summary: ToolSummary = ToolSummarizer.summarize(toolName: toolName, toolInput: toolInput)
        let suggestions: [JSONValue] = payload.permissionSuggestions ?? []
        let request = ApprovalRequest(
            toolName: toolName,
            displayToolName: summary.displayToolName,
            headline: summary.headline,
            summary: summary.summary,
            detail: summary.detail,
            toolInput: toolInput,
            suggestions: suggestions
        )
        store.append(makeItem(id: requestID, session: session, kind: .approval(request), now: now), toolUseID: payload.toolUseId)

        let decision: HookDecision = await broker.hold(requestID, timeout: clampedTimeout())
        switch decision {
        case .approval(let d):
            let resolution: Resolution
            switch d {
            case .allow: resolution = .allowed
            case .allowAlways: resolution = .alwaysAllowed
            case .deny: resolution = .denied
            }
            store.resolveItem(requestID, resolution)
            return HookResponse.encode(HookResponse.value(for: d, suggestions: suggestions))
        case .release, .answers:
            store.resolveItem(requestID, .answeredInTerminal)
            return HookResponse.emptyData
        }
    }

    private func holdQuestion(payload: HookPayload, session: SessionInfo, requestID: UUID, now: Date) async -> Data {
        let toolInput: JSONValue = payload.toolInput ?? .object([:])
        guard let questions = ToolSummarizer.parseQuestions(toolInput: toolInput) else {
            return HookResponse.emptyData
        }
        if broker.heldCount >= HookRouter.maxHeldRequests { return HookResponse.emptyData }
        store.append(makeItem(id: requestID, session: session, kind: .question(questions), now: now), toolUseID: payload.toolUseId)

        let decision: HookDecision = await broker.hold(requestID, timeout: clampedTimeout())
        switch decision {
        case .answers(let answers):
            store.resolveItem(requestID, .answered)
            return HookResponse.encode(HookResponse.answer(toolInput: toolInput, answers: answers))
        case .release, .approval:
            store.resolveItem(requestID, .answeredInTerminal)
            return HookResponse.emptyData
        }
    }

    // MARK: observe flows

    private func handleNotification(payload: HookPayload, session: SessionInfo, now: Date) {
        let type: String = payload.notificationType ?? ""
        switch type {
        case "permission_prompt":
            if !store.hasRecentBlockingItem(sessionID: session.id, kind: .approval, now: now) {
                let info = AttentionInfo(title: "Waiting for you", message: "Approve in terminal", notificationType: type)
                store.append(makeItem(id: UUID(), session: session, kind: .attention(info), now: now))
            }
        case "elicitation_dialog":
            if !store.hasRecentBlockingItem(sessionID: session.id, kind: .question, now: now) {
                let info = AttentionInfo(title: "Waiting for you", message: "Answer in terminal", notificationType: type)
                store.append(makeItem(id: UUID(), session: session, kind: .attention(info), now: now))
            }
        default:
            // idle_prompt is handled by the reducer (session .attention); auth_success,
            // agent_completed and unknown types are activity only.
            break
        }
    }

    // MARK: helpers

    private func makeItem(id: UUID, session: SessionInfo, kind: NotchItem.Kind, now: Date) -> NotchItem {
        return NotchItem(
            id: id,
            sessionID: session.id,
            projectName: session.projectName,
            cwd: session.cwd,
            createdAt: now,
            kind: kind,
            state: .pending
        )
    }

    private func clampedTimeout() -> TimeInterval {
        return min(max(settings.holdTimeout, 1), 115)
    }
}
