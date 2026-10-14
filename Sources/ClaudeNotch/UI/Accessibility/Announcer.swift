import AppKit

/// Posts VoiceOver announcements for new approvals and questions.
enum Announcer {
    @MainActor
    static func announce(_ text: String) {
        let info: [NSAccessibility.NotificationUserInfoKey: Any] = [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue
        ]
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: info)
    }

    @MainActor
    static func announce(item: NotchItem) {
        switch item.kind {
        case .approval(let req):
            announce("\(req.headline) \(req.displayToolName) in \(item.projectName). Approval needed.")
        case .question(let req):
            let q = req.questions.first?.question ?? "a question"
            announce("Claude asks in \(item.projectName): \(q)")
        default:
            break
        }
    }
}
