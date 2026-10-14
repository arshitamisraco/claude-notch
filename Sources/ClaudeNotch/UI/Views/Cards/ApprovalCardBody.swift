import SwiftUI

/// Approval: headline, command/path code block, Deny / Always allow / Allow, "Answer in terminal".
struct ApprovalCardBody: View {
    let item: NotchItem
    let request: ApprovalRequest
    let vm: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm + 2) {
            Text(request.headline)
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)

            let code: String = {
                if let detail = request.detail, !detail.isEmpty { return detail }
                return request.summary
            }()
            if !code.isEmpty {
                CodeBlock(text: code)
            }

            if item.isPending {
                HStack(spacing: Theme.Space.sm) {
                    NotchButton(
                        title: "Deny",
                        hint: "\u{2318}\u{232B}",
                        kind: .dangerGhost,
                        accessibilityText: "Deny \(request.displayToolName) command in \(item.projectName)"
                    ) { vm.deny(item) }
                    Spacer(minLength: 0)
                    if request.canAlwaysAllow {
                        NotchButton(
                            title: "Always allow",
                            hint: "\u{2325}\u{2318}\u{21A9}",
                            kind: .secondary,
                            accessibilityText: "Always allow \(request.displayToolName) in \(item.projectName)"
                        ) { vm.allowAlways(item) }
                    }
                    NotchButton(
                        title: "Allow",
                        hint: "\u{2318}\u{21A9}",
                        kind: .primary,
                        accessibilityText: "Allow \(request.displayToolName) command in \(item.projectName)"
                    ) { vm.allow(item) }
                }
                NotchButton(title: "Answer in terminal", kind: .ghost) { vm.handOff(item) }
                    .padding(.leading, -Theme.Space.sm)
            }
        }
    }
}
