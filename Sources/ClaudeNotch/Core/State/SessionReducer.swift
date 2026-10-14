import Foundation

/// Pure session logic. `status` produced here is the *base* status; NotchStore overlays
/// pending items on top (approval/question/attention).
enum SessionReducer {
    static func projectName(for cwd: String?) -> String {
        guard let cwd = cwd, !cwd.isEmpty else { return "Claude" }
        let last: String = URL(fileURLWithPath: cwd).lastPathComponent
        return last.isEmpty ? "Claude" : last
    }

    static func reduce(_ current: SessionInfo?, payload: HookPayload, terminal: TerminalHint = .unknown, now: Date) -> SessionInfo {
        var s: SessionInfo
        if let current = current {
            s = current
        } else {
            let cwd: String = payload.cwd ?? ""
            s = SessionInfo(
                id: payload.sessionId,
                cwd: cwd,
                projectName: projectName(for: cwd),
                status: .idle,
                activity: nil,
                activityStartedAt: now,
                startedAt: now,
                lastEventAt: now,
                pendingItemCount: 0,
                permissionMode: nil,
                terminal: .unknown
            )
        }

        if let cwd = payload.cwd, !cwd.isEmpty {
            s.cwd = cwd
            s.projectName = projectName(for: cwd)
        }
        if let mode = payload.permissionMode, !mode.isEmpty { s.permissionMode = mode }
        if let b = terminal.bundleID { s.terminal.bundleID = b }
        if let t = terminal.termProgram { s.terminal.termProgram = t }
        s.lastEventAt = now

        func setActivity(_ text: String?) {
            if s.activity != text {
                s.activity = text
                s.activityStartedAt = now
            }
        }

        switch payload.event {
        case .sessionStart:
            s.status = .idle
            setActivity(nil)
        case .userPromptSubmit:
            s.status = .working
            setActivity("Thinking")
        case .preToolUse:
            s.status = .working
            setActivity(ToolSummarizer.activityText(toolName: payload.toolName ?? "tool"))
        case .postToolUse:
            s.status = .working
            setActivity("Thinking")
        case .postToolUseFailure:
            s.status = .working
            let name: String = ToolSummarizer.displayName(for: payload.toolName ?? "Tool")
            setActivity("\(name) failed")
        case .permissionRequest:
            s.status = .working
            setActivity("Waiting for approval")
        case .notification:
            if payload.notificationType == "idle_prompt" {
                s.status = .attention
                setActivity("Waiting for you")
            }
        case .stop:
            if payload.stopHookActive != true {
                s.status = .done
                setActivity("Finished")
            }
        case .subagentStop:
            setActivity("Subagent finished")
        case .sessionEnd:
            s.status = .idle
            setActivity(nil)
        case .unknown:
            break
        }
        return s
    }

    /// Whether `payload` releases a pending blocking item ("Answered in terminal", PLAN §3).
    static func shouldRelease(item: NotchItem, itemToolUseID: String?, by payload: HookPayload) -> Bool {
        guard item.isPending, item.isBlocking, item.sessionID == payload.sessionId else { return false }
        switch payload.event {
        case .userPromptSubmit, .stop, .sessionEnd:
            return true
        case .postToolUse, .postToolUseFailure:
            if let a = itemToolUseID, let b = payload.toolUseId {
                return a == b
            }
            switch item.kind {
            case .approval(let request):
                guard let name = payload.toolName, name == request.toolName else { return false }
                let incoming: String = ToolSummarizer.fingerprint(toolName: name, toolInput: payload.toolInput ?? .object([:]))
                let own: String = ToolSummarizer.fingerprint(toolName: request.toolName, toolInput: request.toolInput)
                return incoming == own
            case .question:
                return payload.toolName == "AskUserQuestion"
            default:
                return false
            }
        default:
            return false
        }
    }
}
