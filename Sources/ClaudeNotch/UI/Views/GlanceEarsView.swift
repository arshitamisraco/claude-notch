import SwiftUI

/// Glance: status dot in the left ear, count / elapsed / check in the right ear. The notch stays empty.
struct GlanceEarsView: View {
    let vm: NotchViewModel

    var body: some View {
        let store = vm.store
        HStack(spacing: 0) {
            ZStack {
                StatusDot(status: store.aggregateStatus, size: 8)
            }
            .frame(width: Theme.Layout.earWidth)

            Spacer(minLength: 0)
                .frame(width: vm.layoutNotchWidth)

            ZStack {
                rightEar(store: store)
            }
            .frame(width: Theme.Layout.earWidth)
        }
        .frame(height: vm.layoutNotchHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(store: store))
    }

    @ViewBuilder
    private func rightEar(store: NotchStore) -> some View {
        let pending = store.pendingItems.count
        if vm.showCheck {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.success)
                .transition(.opacity)
        } else if pending > 0 {
            Text("\(pending)")
                .font(Theme.Typo.micro)
                .tracking(0.2)
                .foregroundStyle(store.aggregateStatus.dotColor)
        } else if let first = store.sessions.first(where: { $0.status != .idle }) {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                Text(Fmt.duration(since: first.activityStartedAt, now: context.date))
                    .font(Theme.Typo.micro)
                    .tracking(0.2)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func accessibilitySummary(store: NotchStore) -> String {
        let pending = store.pendingItems.count
        if pending > 0 { return "Claude Notch, \(pending) waiting for you" }
        switch store.aggregateStatus {
        case .working: return "Claude Notch, Claude is working"
        case .done: return "Claude Notch, finished"
        case .error: return "Claude Notch, error"
        default: return "Claude Notch"
        }
    }
}
