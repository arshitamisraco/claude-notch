import AppKit
import Foundation
import Observation

enum SettingsTab: Hashable {
    case general, hooks, about
}

/// Owns the long-lived objects shared by the AppKit delegate and the SwiftUI scenes.
@MainActor @Observable
final class AppEnvironment {
    static let shared = AppEnvironment()

    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored let core: CoreRuntime
    @ObservationIgnored let hooks: HooksController
    @ObservationIgnored private(set) var panel: NotchPanelController?
    @ObservationIgnored private var terminalFocuser: TerminalFocuser?
    @ObservationIgnored private var soundPlayer: SoundPlayer?
    @ObservationIgnored private var didBootstrap = false

    var settingsTab: SettingsTab = .general

    private init() {
        let settings = AppSettings()
        self.settings = settings
        self.core = CoreRuntime(settings: settings)
        self.hooks = HooksController(settings: settings)
    }

    /// PLAN §2.4 bootstrap.
    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        NSApp.setActivationPolicy(.accessory)

        let focuser = TerminalFocuser()
        terminalFocuser = focuser
        core.store.terminalFocuser = { session in focuser.focus(session) }

        let sounds = SoundPlayer(settings)
        soundPlayer = sounds
        core.store.addArrivalObserver { item in sounds.play(item) }

        core.start()

        let panel = NotchPanelController(store: core.store, settings: settings)
        self.panel = panel
        panel.show()

        wireSettingsCallbacks()

        hooks.refresh()
        if hooks.status == .notInstalled && !settings.didShowHooksOnboarding {
            settings.didShowHooksOnboarding = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.openSettings(tab: .hooks)
            }
        }
    }

    private func wireSettingsCallbacks() {
        settings.onServerChange = { [weak self] in
            guard let self = self else { return }
            self.core.restart()
            self.hooks.reinstallIfInstalled()
        }
        settings.onHooksConfigChange = { [weak self] in
            self?.hooks.reinstallIfInstalled()
        }
        settings.onSettingsPathChange = { [weak self] in
            self?.hooks.refresh()
        }
        settings.onUIChange = { [weak self] in
            self?.panel?.settingsDidChange()
        }
    }

    func shutdown() {
        core.shutdown()
    }

    /// The only place the app is allowed to activate itself.
    func openSettings(tab: SettingsTab = .general) {
        settingsTab = tab
        hooks.refresh()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppEnvironment.shared.bootstrap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppEnvironment.shared.shutdown()
    }
}
