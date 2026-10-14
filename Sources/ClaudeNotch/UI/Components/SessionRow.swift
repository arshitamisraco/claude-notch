import SwiftUI

/// Session list row: dot · project · activity + elapsed · trailing badge. Click focuses the terminal.
struct SessionRow: View {
    let session: SessionInfo
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Space.sm) {
                StatusDot(status: session.status, size: 8)
                Text(session.projectName)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Space.sm)
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    Text(activityText(now: context.date))
                        .font(Theme.Typo.micro)
                        .tracking(0.2)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                if session.pendingItemCount > 0 {
                    Badge(text: "\(session.pendingItemCount)", tinted: session.status == .approval)
                }
            }
            .padding(.horizontal, Theme.Space.md)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(hovering ? Theme.surfaceHover : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(Theme.fast) { hovering = inside }
        }
        .accessibilityLabel("\(session.projectName), \(session.activity ?? "idle"). Focus terminal")
    }

    private func activityText(now: Date) -> String {
        guard session.status != .idle, let activity = session.activity, !activity.isEmpty else { return "Idle" }
        return "\(activity) \u{00B7} \(Fmt.duration(since: session.activityStartedAt, now: now))"
    }
}
