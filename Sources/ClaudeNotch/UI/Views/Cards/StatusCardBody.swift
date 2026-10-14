import SwiftUI

/// Done / error / attention: message and a Jump to action.
struct StatusCardBody: View {
    let item: NotchItem
    let vm: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm + 2) {
            if let line = item.uiDetailLine, !line.isEmpty {
                Text(line)
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if item.isPending || !isResolved {
                HStack(spacing: Theme.Space.sm) {
                    NotchButton(
                        title: "Jump to",
                        kind: .secondary,
                        accessibilityText: "Jump to \(item.projectName) terminal"
                    ) { vm.jump(to: item) }
                    NotchButton(title: "Dismiss", kind: .ghost) { vm.dismiss(item) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var isResolved: Bool {
        if case .resolved = item.state { return true }
        return false
    }
}
