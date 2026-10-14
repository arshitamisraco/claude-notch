import SwiftUI

/// Card for one item: header, sub-header, kind-specific body, resolution state.
@MainActor
struct EventCard: View {
    let item: NotchItem
    let vm: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm + 2) {
            header
            subHeader
            switch item.kind {
            case .approval(let req):
                ApprovalCardBody(item: item, request: req, vm: vm)
            case .question(let req):
                QuestionCardBody(item: item, request: req, vm: vm)
            case .attention, .done, .error:
                StatusCardBody(item: item, vm: vm)
            }
            if case .resolved(let resolution, _) = item.state, !resolution.label.isEmpty {
                ResolutionRow(label: resolution.label)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            StatusDot(status: item.uiStatus, size: 8, animated: item.isPending)
            Text(item.uiTitle)
                .font(Theme.Typo.title)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Theme.Space.sm)
            TimelineView(.periodic(from: Date(), by: 5)) { context in
                Text(Fmt.elapsed(since: item.createdAt, now: context.date))
                    .font(Theme.Typo.micro)
                    .tracking(0.2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var subHeader: some View {
        let sid = vm.store.session(item.sessionID)?.shortID ?? String(item.sessionID.prefix(6))
        return HStack(spacing: Theme.Space.xs) {
            Text(item.projectName)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Text("\u{00B7}")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.textTertiary)
            Text(sid)
                .font(Theme.Typo.micro)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

@MainActor
struct ResolutionRow: View {
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(Theme.Typo.caption)
        }
        .foregroundStyle(Theme.textSecondary)
        .frame(height: 28)
        .accessibilityElement(children: .combine)
    }
}
