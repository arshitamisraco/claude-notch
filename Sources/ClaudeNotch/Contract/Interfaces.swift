import Foundation

// FROZEN CONTRACT — implemented by Settings/AppSettings.swift (C), consumed by Core (A) and UI (B).

@MainActor protocol CoreSettings: AnyObject {
    var port: UInt16 { get }                 // default 41817
    var authToken: String { get }            // 43-char base64url of 32 random bytes
    var holdTimeout: TimeInterval { get }    // clamped 10...115, default 110
    var showToolFailures: Bool { get }       // default false
}

@MainActor protocol UISettings: AnyObject {
    var displayPreference: DisplayPreference { get }
    var globalHotKeyEnabled: Bool { get }    // ⌃⌥C
    var peekEnabled: Bool { get }
}
