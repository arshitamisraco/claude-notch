import SwiftUI

@MainActor
final class PreviewSettings: UISettings {
    var displayPreference: DisplayPreference = .builtIn
    var globalHotKeyEnabled: Bool = true
    var peekEnabled: Bool = true
}

/// Sample data + hosts for Xcode previews (PreviewProvider; avoids the #Preview macro in SPM builds).
@MainActor
enum PreviewFixtures {
    static let now = Date()

    static let sessions: [SessionInfo] = [
        SessionInfo(
            id: "a1b2c3d4", cwd: "/Users/me/claude-notch", projectName: "claude-notch", status: .approval,
            activity: "Waiting for approval", activityStartedAt: now.addingTimeInterval(-42),
            startedAt: now.addingTimeInterval(-900), lastEventAt: now, pendingItemCount: 1,
            permissionMode: "default", terminal: .unknown),
        SessionInfo(
            id: "e5f6a7b8", cwd: "/Users/me/website", projectName: "website", status: .working,
            activity: "Running Bash", activityStartedAt: now.addingTimeInterval(-130),
            startedAt: now.addingTimeInterval(-3000), lastEventAt: now.addingTimeInterval(-3), pendingItemCount: 0,
            permissionMode: nil, terminal: .unknown),
        SessionInfo(
            id: "c9d0e1f2", cwd: "/Users/me/api", projectName: "api", status: .idle,
            activity: nil, activityStartedAt: now.addingTimeInterval(-600),
            startedAt: now.addingTimeInterval(-7200), lastEventAt: now.addingTimeInterval(-600), pendingItemCount: 0,
            permissionMode: nil, terminal: .unknown)
    ]

    static let approval = NotchItem(
        id: UUID(), sessionID: "a1b2c3d4", projectName: "claude-notch", cwd: "/Users/me/claude-notch",
        createdAt: now.addingTimeInterval(-8),
        kind: .approval(ApprovalRequest(
            toolName: "Bash", displayToolName: "Bash", headline: "Claude wants to run",
            summary: "swift build -c release",
            detail: "swift build -c release && ./scripts/build-app.sh --install\necho done",
            toolInput: .object(["command": .string("swift build -c release")]),
            suggestions: [.object(["type": .string("addRules")])])),
        state: .pending)

    static let question = NotchItem(
        id: UUID(), sessionID: "e5f6a7b8", projectName: "website", cwd: "/Users/me/website",
        createdAt: now.addingTimeInterval(-20),
        kind: .question(QuestionRequest(questions: [
            QuestionPrompt(
                question: "Which framework should I use?", header: "Framework",
                options: [
                    QuestionOption(label: "SwiftUI", description: "Declarative, modern"),
                    QuestionOption(label: "AppKit", description: "Maximum control"),
                    QuestionOption(label: "Both", description: nil)
                ], multiSelect: false),
            QuestionPrompt(
                question: "Which targets?", header: "Targets",
                options: [
                    QuestionOption(label: "macOS", description: nil),
                    QuestionOption(label: "iOS", description: nil)
                ], multiSelect: true)
        ])),
        state: .pending)

    static let done = NotchItem(
        id: UUID(), sessionID: "e5f6a7b8", projectName: "website", cwd: "/Users/me/website",
        createdAt: now.addingTimeInterval(-3),
        kind: .done(DoneInfo(summary: "Refactored the header component and updated tests.")),
        state: .pending)

    static let error = NotchItem(
        id: UUID(), sessionID: "c9d0e1f2", projectName: "api", cwd: "/Users/me/api",
        createdAt: now.addingTimeInterval(-3),
        kind: .error(ErrorInfo(title: "Bash failed", message: "exit status 1: npm test")),
        state: .pending)

    static let resolved = NotchItem(
        id: UUID(), sessionID: "a1b2c3d4", projectName: "claude-notch", cwd: "/Users/me/claude-notch",
        createdAt: now.addingTimeInterval(-8),
        kind: approval.kind, state: .resolved(.allowed, at: now))

    static func viewModel(items: [NotchItem], mode: NotchMode, sessions: [SessionInfo] = PreviewFixtures.sessions) -> NotchViewModel {
        let store = NotchStore.preview(sessions: sessions, items: items)
        let vm = NotchViewModel(store: store, settings: PreviewSettings())
        vm.geometry = NotchGeometry(
            notchWidth: 185, notchHeight: 32, midX: 280, hasNotch: true,
            screenFrame: CGRect(x: 0, y: 0, width: 560, height: 520))
        vm.forcedMode = mode
        vm.peekItemID = items.first?.id
        return vm
    }
}

@MainActor
struct PreviewHost: View {
    let vm: NotchViewModel
    var body: some View {
        NotchRootView(vm: vm)
            .frame(width: Theme.Layout.panelSize.width, height: Theme.Layout.panelSize.height)
            .background(Color(white: 0.2))
    }
}

@MainActor
struct NotchPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            PreviewHost(vm: PreviewFixtures.viewModel(items: [], mode: .idle, sessions: []))
                .previewDisplayName("Idle")
            PreviewHost(vm: PreviewFixtures.viewModel(items: [PreviewFixtures.approval], mode: .glance))
                .previewDisplayName("Glance")
            PreviewHost(vm: PreviewFixtures.viewModel(items: [PreviewFixtures.approval], mode: .peek))
                .previewDisplayName("Peek")
            PreviewHost(vm: PreviewFixtures.viewModel(items: [PreviewFixtures.approval, PreviewFixtures.question], mode: .expanded))
                .previewDisplayName("Expanded approval")
            PreviewHost(vm: PreviewFixtures.viewModel(items: [PreviewFixtures.question], mode: .expanded))
                .previewDisplayName("Expanded question")
            PreviewHost(vm: PreviewFixtures.viewModel(items: [PreviewFixtures.done], mode: .expanded))
                .previewDisplayName("Expanded done")
            PreviewHost(vm: PreviewFixtures.viewModel(items: [PreviewFixtures.error], mode: .expanded))
                .previewDisplayName("Expanded error")
            PreviewHost(vm: PreviewFixtures.viewModel(items: [PreviewFixtures.resolved], mode: .expanded))
                .previewDisplayName("Expanded resolved")
            PreviewHost(vm: PreviewFixtures.viewModel(items: [], mode: .expanded, sessions: []))
                .previewDisplayName("Expanded empty")
        }
    }
}
