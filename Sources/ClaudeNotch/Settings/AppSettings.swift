import Foundation
import Observation
import Security

/// UserDefaults-backed app settings. Conforms to the frozen CoreSettings & UISettings contracts.
///
/// Properties are computed and manually bridged to the Observation registry, so SwiftUI updates
/// while values persist immediately to `defaults`.
@MainActor @Observable
final class AppSettings: CoreSettings, UISettings {
    static let bundleID = "dev.claudenotch.ClaudeNotch"
    static let defaultPort: UInt16 = 41817

    private enum Key {
        static let port = "port"
        static let authToken = "authToken"
        static let holdTimeout = "holdTimeout"
        static let showToolFailures = "showToolFailures"
        static let displayPreference = "displayPreference"
        static let globalHotKeyEnabled = "globalHotKeyEnabled"
        static let peekEnabled = "peekEnabled"
        static let soundsEnabled = "soundsEnabled"
        static let includeTerminalHeaders = "includeTerminalHeaders"
        static let settingsPathOverride = "settingsPathOverride"
        static let didShowHooksOnboarding = "didShowHooksOnboarding"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Called after port or token changes (core restart + hooks reinstall).
    @ObservationIgnored var onServerChange: (@MainActor () -> Void)?
    /// Called after a change that alters the generated hooks JSON (not port/token).
    @ObservationIgnored var onHooksConfigChange: (@MainActor () -> Void)?
    /// Called after UISettings changes (panel.settingsDidChange()).
    @ObservationIgnored var onUIChange: (@MainActor () -> Void)?
    /// Called when the settings.json path override changes.
    @ObservationIgnored var onSettingsPathChange: (@MainActor () -> Void)?

    private(set) var authToken: String
    private(set) var launchAtLoginError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let existing = defaults.string(forKey: Key.authToken) ?? ""
        if existing.count >= 32 {
            self.authToken = existing
        } else {
            let fresh = AppSettings.generateToken()
            defaults.set(fresh, forKey: Key.authToken)
            self.authToken = fresh
        }
    }

    // MARK: Token

    nonisolated static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            for i in 0..<bytes.count { bytes[i] = UInt8.random(in: 0...255) }
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func regenerateToken() {
        let fresh = AppSettings.generateToken()
        defaults.set(fresh, forKey: Key.authToken)
        authToken = fresh
        onServerChange?()
    }

    // MARK: CoreSettings

    var port: UInt16 {
        get {
            access(keyPath: \.port)
            let raw = defaults.integer(forKey: Key.port)
            if raw >= 1024 && raw <= 65535 { return UInt16(raw) }
            return AppSettings.defaultPort
        }
        set {
            let clamped = max(1024, newValue)
            guard clamped != port else { return }
            withMutation(keyPath: \.port) {
                defaults.set(Int(clamped), forKey: Key.port)
            }
            onServerChange?()
        }
    }

    var holdTimeout: TimeInterval {
        get {
            access(keyPath: \.holdTimeout)
            guard defaults.object(forKey: Key.holdTimeout) != nil else { return NotchTiming.defaultHoldTimeout }
            return min(115, max(10, defaults.double(forKey: Key.holdTimeout)))
        }
        set {
            withMutation(keyPath: \.holdTimeout) {
                defaults.set(min(115, max(10, newValue)), forKey: Key.holdTimeout)
            }
        }
    }

    var showToolFailures: Bool {
        get { access(keyPath: \.showToolFailures); return bool(Key.showToolFailures, default: false) }
        set { withMutation(keyPath: \.showToolFailures) { defaults.set(newValue, forKey: Key.showToolFailures) } }
    }

    // MARK: UISettings

    var displayPreference: DisplayPreference {
        get {
            access(keyPath: \.displayPreference)
            let raw = defaults.string(forKey: Key.displayPreference) ?? ""
            return DisplayPreference(rawValue: raw) ?? .builtIn
        }
        set {
            withMutation(keyPath: \.displayPreference) { defaults.set(newValue.rawValue, forKey: Key.displayPreference) }
            onUIChange?()
        }
    }

    var globalHotKeyEnabled: Bool {
        get { access(keyPath: \.globalHotKeyEnabled); return bool(Key.globalHotKeyEnabled, default: true) }
        set {
            withMutation(keyPath: \.globalHotKeyEnabled) { defaults.set(newValue, forKey: Key.globalHotKeyEnabled) }
            onUIChange?()
        }
    }

    var peekEnabled: Bool {
        get { access(keyPath: \.peekEnabled); return bool(Key.peekEnabled, default: true) }
        set {
            withMutation(keyPath: \.peekEnabled) { defaults.set(newValue, forKey: Key.peekEnabled) }
            onUIChange?()
        }
    }

    // MARK: Integration

    var soundsEnabled: Bool {
        get { access(keyPath: \.soundsEnabled); return bool(Key.soundsEnabled, default: false) }
        set { withMutation(keyPath: \.soundsEnabled) { defaults.set(newValue, forKey: Key.soundsEnabled) } }
    }

    var includeTerminalHeaders: Bool {
        get { access(keyPath: \.includeTerminalHeaders); return bool(Key.includeTerminalHeaders, default: true) }
        set {
            withMutation(keyPath: \.includeTerminalHeaders) { defaults.set(newValue, forKey: Key.includeTerminalHeaders) }
            onHooksConfigChange?()
        }
    }

    /// Empty string = default location (`$CLAUDE_CONFIG_DIR` or `~/.claude`).
    var settingsPathOverride: String {
        get { access(keyPath: \.settingsPathOverride); return defaults.string(forKey: Key.settingsPathOverride) ?? "" }
        set {
            withMutation(keyPath: \.settingsPathOverride) { defaults.set(newValue, forKey: Key.settingsPathOverride) }
            onSettingsPathChange?()
        }
    }

    var launchAtLogin: Bool {
        get { access(keyPath: \.launchAtLogin); return LaunchAtLogin.isEnabled }
        set {
            withMutation(keyPath: \.launchAtLogin) {
                do {
                    try LaunchAtLogin.setEnabled(newValue)
                    launchAtLoginError = nil
                } catch {
                    launchAtLoginError = error.localizedDescription
                }
            }
        }
    }

    var didShowHooksOnboarding: Bool {
        get { defaults.bool(forKey: Key.didShowHooksOnboarding) }
        set { defaults.set(newValue, forKey: Key.didShowHooksOnboarding) }
    }

    /// Resolved settings.json location honoring the override.
    var settingsURL: URL {
        let trimmed = settingsPathOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return HooksInstaller.defaultSettingsURL() }
        let expanded = (trimmed as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        if url.pathExtension.lowercased() == "json" { return url }
        return url.appendingPathComponent("settings.json")
    }

    private func bool(_ key: String, default value: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return value }
        return defaults.bool(forKey: key)
    }
}
