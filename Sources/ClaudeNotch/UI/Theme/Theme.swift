import SwiftUI

/// Design tokens (docs/DESIGN.md). Single source of truth for colour, type, spacing, radius and motion.
enum Theme {
    // MARK: Color
    static let surface = Color.black
    static let surfaceRaised = Color.white.opacity(0.06)
    static let surfaceHover = Color.white.opacity(0.10)
    static let stroke = Color.white.opacity(0.08)
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.60)
    static let textTertiary = Color.white.opacity(0.38)
    static let accent = Color(hex: 0xD97757)
    static let attention = Color(hex: 0xF5B544)
    static let approval = Color(hex: 0x7AA2F7)
    static let success = Color(hex: 0x4ADE80)
    static let danger = Color(hex: 0xF87171)

    // MARK: Typography
    enum Typo {
        static let title = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 12, weight: .regular)
        static let caption = Font.system(size: 11, weight: .medium)
        static let micro = Font.system(size: 10, weight: .medium)
        static let code = Font.system(size: 11, weight: .regular, design: .monospaced)
        static let button = Font.system(size: 12, weight: .semibold)
    }

    // MARK: Spacing (4pt grid)
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: Radius
    enum Radius {
        static let notchBottomCollapsed: CGFloat = 10
        static let notchBottomExpanded: CGFloat = 22
        static let row: CGFloat = 10
        static let button: CGFloat = 8
        /// Inverse top fillet that melts the pill into the bezel.
        static let fillet: CGFloat = 8
    }

    // MARK: Layout
    enum Layout {
        static let panelSize = CGSize(width: 560, height: 520)
        static let earWidth: CGFloat = 36
        static let peekWidth: CGFloat = 420
        static let peekExtraHeight: CGFloat = 64
        static let expandedWidth: CGFloat = 460
        static let expandedMaxHeight: CGFloat = 420
        static let virtualNotch = CGSize(width: 200, height: 32)
        static let hitSlop: CGFloat = 4
    }

    // MARK: Motion
    static let springExpand = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let springCollapse = Animation.spring(response: 0.32, dampingFraction: 0.9)
    static let fast = Animation.easeOut(duration: 0.15)
    static let crossfade = Animation.easeInOut(duration: 0.2)
    static let pulsePeriod: Double = 1.6
    static let shimmerPeriod: Double = 2.0

    static func animation(for mode: NotchMode, reduceMotion: Bool) -> Animation {
        if reduceMotion { return crossfade }
        return mode == .expanded ? springExpand : springCollapse
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

/// Small formatting helpers shared by views.
enum Fmt {
    /// "now", "12s", "3m", "2h".
    static func elapsed(since date: Date, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 5 { return "now" }
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h"
    }

    /// Like `elapsed` but never "now" (for running durations).
    static func duration(since date: Date, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h"
    }
}

extension SessionStatus {
    var dotColor: Color {
        switch self {
        case .idle: return Theme.textTertiary
        case .working: return Theme.accent
        case .done: return Theme.success
        case .error: return Theme.danger
        case .attention, .question: return Theme.attention
        case .approval: return Theme.approval
        }
    }
}
