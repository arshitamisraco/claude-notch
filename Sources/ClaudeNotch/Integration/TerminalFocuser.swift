import AppKit
import Foundation

/// Brings the app hosting a Claude Code session to the front (PLAN §5 C).
/// Order: bundle id header, TERM_PROGRAM map, editor cwd open, Claude desktop app, last-known terminal.
@MainActor
final class TerminalFocuser {
    static let claudeDesktopBundleID = "com.anthropic.claudefordesktop"

    static let termProgramMap: [String: String] = [
        "Apple_Terminal": "com.apple.Terminal",
        "iTerm.app": "com.googlecode.iterm2",
        "vscode": "com.microsoft.VSCode",
        "ghostty": "com.mitchellh.ghostty",
        "WezTerm": "com.github.wez.wezterm",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "kitty": "net.kovidgoyal.kitty",
        "alacritty": "org.alacritty",
        "zed": "dev.zed.Zed",
    ]

    /// Editors where opening the project folder focuses the right window.
    static let editorBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "dev.zed.Zed",
        "com.todesktop.230313mzl4w4u92",   // Cursor
        "com.exafunction.windsurf",
    ]

    private var lastKnownBundleID: String?

    init() {}

    func focus(_ session: SessionInfo) {
        var candidates: [String] = []
        if let id = Self.clean(session.terminal.bundleID) { candidates.append(id) }
        if let term = Self.clean(session.terminal.termProgram), let id = Self.termProgramMap[term] {
            candidates.append(id)
        }
        candidates.append(Self.claudeDesktopBundleID)
        if let last = lastKnownBundleID { candidates.append(last) }

        for bundleID in candidates {
            if open(bundleID: bundleID, cwd: session.cwd) {
                if bundleID != Self.claudeDesktopBundleID { lastKnownBundleID = bundleID }
                return
            }
        }
    }

    /// Header values that still start with "$" were never interpolated: treat as absent.
    private static func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty, !value.hasPrefix("$") else {
            return nil
        }
        return value
    }

    private func open(bundleID: String, cwd: String) -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        var isDir: ObjCBool = false
        if Self.editorBundleIDs.contains(bundleID), !cwd.isEmpty,
           FileManager.default.fileExists(atPath: cwd, isDirectory: &isDir), isDir.boolValue {
            NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: appURL, configuration: config, completionHandler: nil)
        } else {
            NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
        }
        return true
    }
}
