import AppKit
import Foundation
import Observation

enum HooksStatus: Equatable {
    case notInstalled
    case installed
    case outdated            // our hooks exist but differ (port, token, headers, version)
    case settingsUnreadable  // malformed / unreadable; we never write in this state
    case hooksDisabled       // "disableAllHooks": true in settings.json
}

enum HooksInstallerError: LocalizedError {
    case settingsUnreadable(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .settingsUnreadable(let detail):
            return "settings.json could not be read (\(detail)). Nothing was changed."
        case .writeFailed(let detail):
            return "Could not write settings.json (\(detail))."
        }
    }
}

enum HooksInstallOutcome: Equatable {
    case unchanged
    case written(backup: URL?)
}

/// Safe-merge installer for Claude Code hooks. Pure file IO; no UI. See PLAN §5 C.
final class HooksInstaller {
    static let marker = HooksConfig.marker
    static let backupPrefix = "settings.json.claude-notch.bak-"
    static let maxBackups = 5

    let fileURL: URL
    private let fileManager: FileManager
    private let now: () -> Date

    init(fileURL: URL = HooksInstaller.defaultSettingsURL(),
         fileManager: FileManager = .default,
         now: @escaping () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.now = now
    }

    static func defaultSettingsURL() -> URL {
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            let expanded = (dir as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded).appendingPathComponent("settings.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("settings.json")
    }

    /// The real file we read/write (symlinks resolved).
    var resolvedURL: URL { fileURL.resolvingSymlinksInPath() }

    // MARK: Reading

    /// Returns the parsed root object (`[:]` when the file is missing or blank).
    func readSettings() throws -> [String: Any] {
        let url = resolvedURL
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw HooksInstallerError.settingsUnreadable(error.localizedDescription)
        }
        let text = String(decoding: data, as: UTF8.self)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw HooksInstallerError.settingsUnreadable("invalid JSON")
        }
        guard let dict = object as? [String: Any] else {
            throw HooksInstallerError.settingsUnreadable("top level is not an object")
        }
        if let hooks = dict["hooks"], !(hooks is [String: Any]) {
            throw HooksInstallerError.settingsUnreadable("\"hooks\" is not an object")
        }
        return dict
    }

    // MARK: Status

    func status(for config: HooksConfig) -> HooksStatus {
        let root: [String: Any]
        do { root = try readSettings() } catch { return .settingsUnreadable }
        let existing = HooksInstaller.ourHandlers(in: root)
        if (root["disableAllHooks"] as? Bool) == true { return .hooksDisabled }
        if existing.isEmpty { return .notInstalled }
        let desired = HooksInstaller.ourHandlers(in: config.document())
        return existing == desired ? .installed : .outdated
    }

    /// True if any handler with our marker is present (regardless of version).
    func hasInstalledHooks() -> Bool {
        guard let root = try? readSettings() else { return false }
        return !HooksInstaller.ourHandlers(in: root).isEmpty
    }

    /// Human-readable description of what install/update/uninstall would do.
    func diffSummary(for config: HooksConfig) -> String {
        let root: [String: Any]
        do { root = try readSettings() } catch {
            return "settings.json can't be parsed. Fix or remove it, then try again. Claude Notch won't modify it."
        }
        let existing = HooksInstaller.ourHandlers(in: root)
        let desired = HooksInstaller.ourHandlers(in: config.document())
        if existing.isEmpty {
            return "Will add \(desired.count) hook entries to \(fileURL.path). Your other settings and hooks stay untouched. A backup is made first."
        }
        if existing == desired {
            return "Up to date: \(existing.count) Claude Notch hook entries on port \(config.port)."
        }
        return "Will replace \(existing.count) existing Claude Notch entries with \(desired.count) current ones. Other hooks stay untouched."
    }

    // MARK: Install / uninstall

    @discardableResult
    func install(config: HooksConfig) throws -> HooksInstallOutcome {
        let root = try readSettings()
        let desired = HooksInstaller.ourHandlers(in: config.document())
        if HooksInstaller.ourHandlers(in: root) == desired { return .unchanged }
        let merged = try HooksInstaller.merge(root: root, desired: config.eventGroups())
        return try write(merged)
    }

    @discardableResult
    func uninstall() throws -> HooksInstallOutcome {
        let root = try readSettings()
        if HooksInstaller.ourHandlers(in: root).isEmpty { return .unchanged }
        let merged = try HooksInstaller.merge(root: root, desired: nil)
        return try write(merged)
    }

    // MARK: Merge (pure)

    static func isOurs(_ handler: Any) -> Bool {
        guard let dict = handler as? [String: Any], let url = dict["url"] as? String else { return false }
        return url.contains(marker)
    }

    /// Removes every handler we own, drops groups/event keys only if we emptied them, then appends `desired`.
    static func merge(root: [String: Any], desired: [String: [[String: Any]]]?) throws -> [String: Any] {
        var result = root
        var hooks: [String: Any] = [:]
        let hadHooksKey = root["hooks"] != nil
        if let existing = root["hooks"] {
            guard let dict = existing as? [String: Any] else {
                throw HooksInstallerError.settingsUnreadable("\"hooks\" is not an object")
            }
            hooks = dict
        }
        let wasEmpty = hooks.isEmpty

        for event in Array(hooks.keys) {
            guard let groups = hooks[event] as? [Any] else { continue }
            var newGroups: [Any] = []
            var changed = false
            for entry in groups {
                guard var group = entry as? [String: Any], let handlers = group["hooks"] as? [Any] else {
                    newGroups.append(entry)
                    continue
                }
                let kept = handlers.filter { !isOurs($0) }
                if kept.count == handlers.count {
                    newGroups.append(entry)
                    continue
                }
                changed = true
                if kept.isEmpty { continue }   // we emptied this group
                group["hooks"] = kept
                newGroups.append(group)
            }
            if changed {
                if newGroups.isEmpty { hooks[event] = nil } else { hooks[event] = newGroups }
            }
        }

        if let desired = desired {
            for (event, groups) in desired {
                var array: [Any] = []
                if let current = hooks[event] {
                    guard let existingArray = current as? [Any] else {
                        throw HooksInstallerError.settingsUnreadable("hooks.\(event) is not an array")
                    }
                    array = existingArray
                }
                array.append(contentsOf: groups as [Any])
                hooks[event] = array
            }
        }

        if hooks.isEmpty {
            if hadHooksKey && wasEmpty { result["hooks"] = hooks } else { result["hooks"] = nil }
        } else {
            result["hooks"] = hooks
        }
        return result
    }

    /// Canonical, sorted descriptions of our handlers ("event|matcher|json") for comparison.
    static func ourHandlers(in root: [String: Any]) -> [String] {
        guard let hooks = root["hooks"] as? [String: Any] else { return [] }
        var out: [String] = []
        for (event, value) in hooks {
            guard let groups = value as? [Any] else { continue }
            for entry in groups {
                guard let group = entry as? [String: Any], let handlers = group["hooks"] as? [Any] else { continue }
                let matcher = (group["matcher"] as? String) ?? ""
                for handler in handlers where isOurs(handler) {
                    guard JSONSerialization.isValidJSONObject(handler),
                          let data = try? JSONSerialization.data(withJSONObject: handler, options: [.sortedKeys]) else { continue }
                    out.append("\(event)|\(matcher)|" + String(decoding: data, as: UTF8.self))
                }
            }
        }
        return out.sorted()
    }

    // MARK: Writing

    private func write(_ root: [String: Any]) throws -> HooksInstallOutcome {
        let url = resolvedURL
        let existed = fileManager.fileExists(atPath: url.path)
        guard JSONSerialization.isValidJSONObject(root) else {
            throw HooksInstallerError.writeFailed("result is not valid JSON")
        }
        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: root,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        } catch {
            throw HooksInstallerError.writeFailed(error.localizedDescription)
        }
        var data = body
        data.append(0x0A)

        var backupURL: URL?
        var permissions: NSNumber?
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if existed {
                permissions = (try? fileManager.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber
                backupURL = try makeBackup(of: url)
            }
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: permissions ?? NSNumber(value: 0o600)],
                                          ofItemAtPath: url.path)
        } catch {
            throw HooksInstallerError.writeFailed(error.localizedDescription)
        }
        pruneBackups(in: url.deletingLastPathComponent())
        return .written(backup: backupURL)
    }

    private func makeBackup(of url: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now())
        let dir = url.deletingLastPathComponent()
        var candidate = dir.appendingPathComponent(HooksInstaller.backupPrefix + stamp)
        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent(HooksInstaller.backupPrefix + stamp + "-\(counter)")
            counter += 1
        }
        try fileManager.copyItem(at: url, to: candidate)
        return candidate
    }

    private func backups(in dir: URL) -> [URL] {
        let names = (try? fileManager.contentsOfDirectory(atPath: dir.path)) ?? []
        return names
            .filter { $0.hasPrefix(HooksInstaller.backupPrefix) }
            .sorted()
            .map { dir.appendingPathComponent($0) }
    }

    private func pruneBackups(in dir: URL) {
        let all = backups(in: dir)
        guard all.count > HooksInstaller.maxBackups else { return }
        for old in all.prefix(all.count - HooksInstaller.maxBackups) {
            try? fileManager.removeItem(at: old)
        }
    }

    /// Newest backup next to the resolved settings file, if any.
    func latestBackupURL() -> URL? {
        backups(in: resolvedURL.deletingLastPathComponent()).last
    }
}

// MARK: - UI-facing controller

@MainActor @Observable
final class HooksController {
    private(set) var status: HooksStatus = .notInstalled
    private(set) var message: String?
    private(set) var diffSummary: String = ""
    private(set) var settingsPath: String = ""
    private(set) var hasBackup: Bool = false

    @ObservationIgnored private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    private var config: HooksConfig {
        HooksConfig(port: settings.port, token: settings.authToken,
                    includeTerminalHeaders: settings.includeTerminalHeaders)
    }

    private func makeInstaller() -> HooksInstaller {
        HooksInstaller(fileURL: settings.settingsURL)
    }

    var isInstalled: Bool { status == .installed }

    func refresh() {
        let installer = makeInstaller()
        status = installer.status(for: config)
        diffSummary = installer.diffSummary(for: config)
        settingsPath = installer.fileURL.path
        hasBackup = installer.latestBackupURL() != nil
    }

    func install() {
        let installer = makeInstaller()
        do {
            let outcome = try installer.install(config: config)
            switch outcome {
            case .unchanged: message = "Hooks are already up to date."
            case .written: message = "Hooks installed. New Claude Code sessions pick them up automatically."
            }
        } catch {
            message = error.localizedDescription
        }
        refresh()
    }

    func uninstall() {
        let installer = makeInstaller()
        do {
            let outcome = try installer.uninstall()
            message = outcome == .unchanged ? "No Claude Notch hooks were found." : "Hooks removed. Your other hooks were left in place."
        } catch {
            message = error.localizedDescription
        }
        refresh()
    }

    /// Rewrites hooks after a port/token/header change, only if we had installed them.
    func reinstallIfInstalled() {
        let installer = makeInstaller()
        if installer.hasInstalledHooks() {
            install()
        } else {
            refresh()
        }
    }

    func revealBackup() {
        let installer = makeInstaller()
        if let backup = installer.latestBackupURL() {
            NSWorkspace.shared.activateFileViewerSelecting([backup])
        } else if FileManager.default.fileExists(atPath: installer.resolvedURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([installer.resolvedURL])
        }
    }

    var statusLabel: String {
        switch status {
        case .notInstalled: return "Not installed"
        case .installed: return "Installed"
        case .outdated: return "Update available"
        case .settingsUnreadable: return "settings.json unreadable"
        case .hooksDisabled: return "Hooks disabled in settings"
        }
    }
}
