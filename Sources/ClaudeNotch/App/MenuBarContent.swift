import AppKit
import SwiftUI

@MainActor
struct MenuBarContent: View {
    let env: AppEnvironment

    private var store: NotchStore { env.core.store }

    private var serverText: String {
        switch store.serverState {
        case .stopped: return "Server stopped"
        case .listening(let port): return "Listening on 127.0.0.1:\(port)"
        case .failed(let message): return message
        }
    }

    private var sessionsText: String {
        let count = store.sessions.count
        let pending = store.pendingItems.count
        var text = count == 1 ? "1 session" : "\(count) sessions"
        if pending > 0 { text += " · \(pending) waiting" }
        return text
    }

    var body: some View {
        Text(serverText)
        Text(sessionsText)

        Divider()

        Button("Toggle Notch") {
            env.panel?.toggleExpanded()
        }

        hooksItem

        Button("Settings…") {
            env.openSettings(tab: .general)
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Claude Notch") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private var hooksItem: some View {
        switch env.hooks.status {
        case .installed:
            Button("Hooks installed") {}.disabled(true)
        case .outdated:
            Button("Update Hooks") { env.hooks.install() }
        case .notInstalled:
            Button("Install Hooks") { env.hooks.install() }
        case .hooksDisabled:
            Button("Hooks disabled in settings…") { env.openSettings(tab: .hooks) }
        case .settingsUnreadable:
            Button("settings.json unreadable…") { env.openSettings(tab: .hooks) }
        }
    }
}
