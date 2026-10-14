import SwiftUI

/// Expanded: top bar beside the camera, active card, session list.
struct ExpandedView: View {
    let vm: NotchViewModel

    var body: some View {
        let store = vm.store
        VStack(alignment: .leading, spacing: 0) {
            topBar(store: store)

            if let item = vm.currentItem {
                EventCard(item: item, vm: vm)
                    .id(item.id)
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.top, Theme.Space.xs)
                    .padding(.bottom, Theme.Space.md)
                    .transition(.opacity)
            }

            sessionList(store: store, hasCard: vm.currentItem != nil)
        }
        .padding(.bottom, Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Top bar

    private func topBar(store: NotchStore) -> some View {
        let side = max(60, (Theme.Layout.expandedWidth - vm.layoutNotchWidth) / 2 - Theme.Space.lg)
        return HStack(spacing: 0) {
            HStack(spacing: Theme.Space.sm) {
                StatusDot(status: store.aggregateStatus, size: 8)
                Text(summary(store: store))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: side, alignment: .leading)

            Spacer(minLength: vm.layoutNotchWidth)

            pager(store: store)
                .frame(width: side, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Space.lg)
        .frame(height: vm.layoutNotchHeight)
    }

    private func summary(store: NotchStore) -> String {
        let pending = store.pendingItems.count
        if pending > 0 { return pending == 1 ? "1 waiting" : "\(pending) waiting" }
        switch store.aggregateStatus {
        case .working: return "Working"
        case .error: return "Error"
        case .done: return "Finished"
        default: return "Claude"
        }
    }

    @ViewBuilder
    private func pager(store: NotchStore) -> some View {
        let pos = vm.pagerPosition
        if pos.total > 1 {
            HStack(spacing: Theme.Space.xs) {
                pagerButton(symbol: "chevron.left", label: "Previous item", enabled: pos.index > 0) { vm.previousItem() }
                Text("\(pos.index + 1) of \(pos.total)")
                    .font(Theme.Typo.micro)
                    .tracking(0.2)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                pagerButton(symbol: "chevron.right", label: "Next item", enabled: pos.index + 1 < pos.total) { vm.nextItem() }
            }
        }
    }

    private func pagerButton(symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(enabled ? Theme.textSecondary : Theme.textTertiary.opacity(0.5))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: Sessions

    @ViewBuilder
    private func sessionList(store: NotchStore, hasCard: Bool) -> some View {
        let sessions = store.sessions
        if sessions.isEmpty {
            if !hasCard {
                emptyState(store: store)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if hasCard {
                    Rectangle()
                        .fill(Theme.stroke)
                        .frame(height: 0.5)
                        .padding(.horizontal, Theme.Space.lg)
                        .padding(.bottom, Theme.Space.sm)
                }
                VStack(spacing: Theme.Space.xxs) {
                    ForEach(sessions) { session in
                        SessionRow(session: session) { vm.jump(to: session) }
                    }
                }
                .padding(.horizontal, Theme.Space.sm)
            }
        }
    }

    private func emptyState(store: NotchStore) -> some View {
        VStack(spacing: Theme.Space.xs) {
            Text("No active sessions")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.textSecondary)
            switch store.serverState {
            case .failed(let message):
                Text(message)
                    .font(Theme.Typo.micro)
                    .foregroundStyle(Theme.danger)
            case .listening(let port):
                Text("Listening on port \(String(port))")
                    .font(Theme.Typo.micro)
                    .foregroundStyle(Theme.textTertiary)
            case .stopped:
                Text("Server stopped")
                    .font(Theme.Typo.micro)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.lg)
    }
}
