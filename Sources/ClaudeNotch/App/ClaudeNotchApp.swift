import SwiftUI

@main
struct ClaudeNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Claude Notch", systemImage: "sparkle") {
            MenuBarContent(env: AppEnvironment.shared)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(env: AppEnvironment.shared)
        }
    }
}
