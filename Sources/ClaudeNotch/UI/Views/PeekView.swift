import SwiftUI

/// Peek: one-line headline + project, shown below the camera row.
struct PeekView: View {
    let vm: NotchViewModel
    let item: NotchItem

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            StatusDot(status: item.uiStatus, size: 8)
            VStack(alignment: .leading, spacing: 2) {
                if case .resolved(let resolution, _) = item.state, !resolution.label.isEmpty {
                    Text(resolution.label)
                        .font(Theme.Typo.title)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                } else {
                    Text(item.uiHeadline)
                        .font(Theme.Typo.title)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Space.sm)
            if item.isBlocking && item.isPending {
                KeyHint(text: "\u{2303}\u{2325}C")
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .frame(height: Theme.Layout.peekExtraHeight, alignment: .center)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.uiHeadline), \(item.projectName)")
    }

    private var subtitle: String {
        if let detail = item.uiDetailLine, !detail.isEmpty {
            return "\(item.projectName) \u{00B7} \(detail)"
        }
        return item.projectName
    }
}
