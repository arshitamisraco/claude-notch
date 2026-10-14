import XCTest
@testable import ClaudeNotch

final class HooksInstallerTests: XCTestCase {
    private var dir: URL!
    private var settingsURL: URL!
    private let config = HooksConfig(port: 41817, token: "TOKEN123", includeTerminalHeaders: true)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-notch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        settingsURL = dir.appendingPathComponent("settings.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: helpers

    private func installer(now: @escaping () -> Date = { Date() }) -> HooksInstaller {
        HooksInstaller(fileURL: settingsURL, now: now)
    }

    private func write(_ json: String) throws {
        try json.data(using: .utf8)!.write(to: settingsURL)
    }

    private func readRoot() throws -> [String: Any] {
        let data = try Data(contentsOf: settingsURL.resolvingSymlinksInPath())
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func backups() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasPrefix(HooksInstaller.backupPrefix) }.sorted()
    }

    private func handlerURLs(_ root: [String: Any], event: String) -> [String] {
        let hooks = root["hooks"] as? [String: Any]
        let groups = hooks?[event] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["url"] as? String } }
    }

    private let userSettings = """
    {
      "model": "opus",
      "permissions": { "allow": ["Bash(ls:*)"] },
      "hooks": {
        "Stop": [ { "hooks": [ { "type": "command", "command": "echo done" } ] } ],
        "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "./check.sh" } ] } ]
      }
    }
    """

    // MARK: tests

    func testInstallCreatesFileWhenMissing() throws {
        let outcome = try installer().install(config: config)
        XCTAssertEqual(outcome, .written(backup: nil))
        XCTAssertEqual(installer().status(for: config), .installed)
        let root = try readRoot()
        XCTAssertEqual(HooksInstaller.ourHandlers(in: root).count, config.handlerCount)
        XCTAssertEqual(handlerURLs(root, event: "PermissionRequest"),
                       ["http://127.0.0.1:41817/claude-notch/v1/hook"])
    }

    func testInstallIsIdempotent() throws {
        try write(userSettings)
        _ = try installer().install(config: config)
        let first = try Data(contentsOf: settingsURL)
        let backupsAfterFirst = backups()
        let outcome = try installer().install(config: config)
        XCTAssertEqual(outcome, .unchanged)
        XCTAssertEqual(try Data(contentsOf: settingsURL), first)
        XCTAssertEqual(backups(), backupsAfterFirst)
        XCTAssertEqual(HooksInstaller.ourHandlers(in: try readRoot()).count, config.handlerCount)
    }

    func testPreservesUnrelatedHooksAndKeys() throws {
        try write(userSettings)
        _ = try installer().install(config: config)
        let root = try readRoot()
        XCTAssertEqual(root["model"] as? String, "opus")
        XCTAssertNotNil(root["permissions"])
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        let stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stop.count, 2)
        XCTAssertEqual((stop[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String, "echo done")
        let pre = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(pre.first?["matcher"] as? String, "Bash")
        XCTAssertEqual(pre.count, 3)
        XCTAssertEqual(backups().count, 1)
    }

    func testUninstallLeavesUserHooksIntact() throws {
        try write(userSettings)
        let original = try readRoot()
        _ = try installer().install(config: config)
        _ = try installer().uninstall()
        let after = try readRoot()
        XCTAssertTrue(NSDictionary(dictionary: original).isEqual(to: after))
        XCTAssertEqual(installer().status(for: config), .notInstalled)
    }

    func testUninstallRemovesEmptiedHooksKeyAndKeepsOtherKeys() throws {
        try write("{ \"model\": \"sonnet\" }")
        _ = try installer().install(config: config)
        _ = try installer().uninstall()
        let root = try readRoot()
        XCTAssertNil(root["hooks"])
        XCTAssertEqual(root["model"] as? String, "sonnet")
    }

    func testMixedGroupKeepsUserHandler() throws {
        let handlerOurs: [String: Any] = config.handler(path: "event", timeout: 5)
        let userHandler: [String: Any] = ["type": "command", "command": "echo hi"]
        let handlers: [[String: Any]] = [userHandler, handlerOurs]
        let group: [String: Any] = ["hooks": handlers]
        let stopGroups: [[String: Any]] = [group]
        let mixed: [String: Any] = ["hooks": ["Stop": stopGroups] as [String: Any]]
        let data = try JSONSerialization.data(withJSONObject: mixed)
        try data.write(to: settingsURL)
        _ = try installer().uninstall()
        let root = try readRoot()
        let stop = ((root["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]) ?? []
        XCTAssertEqual(stop.count, 1)
        XCTAssertEqual((stop[0]["hooks"] as? [[String: Any]])?.count, 1)
    }

    func testMalformedFileIsNeverWritten() throws {
        let garbage = "{ \"hooks\": { oops "
        try write(garbage)
        XCTAssertEqual(installer().status(for: config), .settingsUnreadable)
        XCTAssertThrowsError(try installer().install(config: config))
        XCTAssertThrowsError(try installer().uninstall())
        XCTAssertEqual(try String(contentsOf: settingsURL), garbage)
        XCTAssertTrue(backups().isEmpty)
    }

    func testNonObjectTopLevelIsUnreadable() throws {
        try write("[1,2,3]")
        XCTAssertEqual(installer().status(for: config), .settingsUnreadable)
        XCTAssertThrowsError(try installer().install(config: config))
        XCTAssertEqual(try String(contentsOf: settingsURL), "[1,2,3]")
    }

    func testOutdatedDetectionAndUpdate() throws {
        _ = try installer().install(config: config)
        let newPort = HooksConfig(port: 42000, token: "TOKEN123", includeTerminalHeaders: true)
        let newToken = HooksConfig(port: 41817, token: "OTHER", includeTerminalHeaders: true)
        XCTAssertEqual(installer().status(for: newPort), .outdated)
        XCTAssertEqual(installer().status(for: newToken), .outdated)
        _ = try installer().install(config: newPort)
        XCTAssertEqual(installer().status(for: newPort), .installed)
        let root = try readRoot()
        XCTAssertEqual(HooksInstaller.ourHandlers(in: root).count, newPort.handlerCount)
        XCTAssertFalse(handlerURLs(root, event: "Stop").contains { $0.contains(":41817") })
    }

    func testHooksDisabledStatus() throws {
        try write("{ \"disableAllHooks\": true }")
        XCTAssertEqual(installer().status(for: config), .hooksDisabled)
    }

    func testNotInstalledForMissingFile() {
        XCTAssertEqual(installer().status(for: config), .notInstalled)
    }

    func testBackupsKeepLastFive() throws {
        try write(userSettings)
        for i in 1...7 {
            let name = HooksInstaller.backupPrefix + String(format: "20240101-0000%02d", i)
            try "{}".write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        _ = try installer().install(config: config)
        let kept = backups()
        XCTAssertEqual(kept.count, 5)
        XCTAssertFalse(kept.contains(HooksInstaller.backupPrefix + "20240101-000001"))
    }

    func testPreservesFilePermissions() throws {
        try write(userSettings)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: settingsURL.path)
        _ = try installer().install(config: config)
        let attrs = try FileManager.default.attributesOfItem(atPath: settingsURL.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o640)
    }

    func testSymlinkIsResolvedAndPreserved() throws {
        let real = dir.appendingPathComponent("real.json")
        try userSettings.data(using: .utf8)!.write(to: real)
        try FileManager.default.createSymbolicLink(at: settingsURL, withDestinationURL: real)
        _ = try installer().install(config: config)
        let dest = try FileManager.default.destinationOfSymbolicLink(atPath: settingsURL.path)
        XCTAssertTrue(dest.hasSuffix("real.json"))
        let data = try Data(contentsOf: real)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(HooksInstaller.ourHandlers(in: root).count, config.handlerCount)
    }

    func testQueryTokenWhenHeadersExcluded() throws {
        let noHeaders = HooksConfig(port: 41817, token: "abc-DEF_123", includeTerminalHeaders: false)
        _ = try installer().install(config: noHeaders)
        let root = try readRoot()
        let urls = handlerURLs(root, event: "PermissionRequest")
        XCTAssertEqual(urls, ["http://127.0.0.1:41817/claude-notch/v1/hook?token=abc-DEF_123"])
        let hooks = root["hooks"] as? [String: Any]
        let group = (hooks?["PermissionRequest"] as? [[String: Any]])?.first
        let handler = (group?["hooks"] as? [[String: Any]])?.first
        XCTAssertNil(handler?["headers"])
        XCTAssertEqual(installer().status(for: noHeaders), .installed)
        XCTAssertEqual(installer().status(for: config), .outdated)
    }

    func testConfigShapeMatchesPlan() {
        let groups = config.eventGroups()
        XCTAssertEqual(Set(groups.keys), [
            "PermissionRequest", "PreToolUse", "PostToolUse", "PostToolUseFailure", "Notification",
            "UserPromptSubmit", "Stop", "SubagentStop", "SessionStart", "SessionEnd",
        ])
        XCTAssertEqual(groups["PreToolUse"]?.count, 2)
        XCTAssertEqual(config.handlerCount, 11)
        let h = config.handler(path: "hook", timeout: 120)
        XCTAssertEqual(h["timeout"] as? Int, 120)
        XCTAssertEqual((h["headers"] as? [String: String])?["X-Claude-Notch-Token"], "TOKEN123")
        XCTAssertEqual(h["allowedEnvVars"] as? [String], ["TERM_PROGRAM", "__CFBundleIdentifier"])
    }
}
