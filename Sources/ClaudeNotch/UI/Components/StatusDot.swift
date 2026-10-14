import SwiftUI

/// Status indicator. working = shimmer, question/approval/attention = pulse; others static.
@MainActor
struct StatusDot: View {
    let status: SessionStatus
    var size: CGFloat = 8
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Motion { case none, shimmer, pulse }

    private var motion: Motion {
        switch status {
        case .working: return .shimmer
        case .question, .approval, .attention: return .pulse
        default: return .none
        }
    }

    var body: some View {
        Group {
            if motion == .none || !animated || reduceMotion {
                dot(opacity: 1, haloScale: 1, haloOpacity: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    if motion == .pulse {
                        let p = (t.truncatingRemainder(dividingBy: Theme.pulsePeriod)) / Theme.pulsePeriod
                        dot(opacity: 1, haloScale: 1 + CGFloat(p) * 1.4, haloOpacity: (1 - p) * 0.55)
                    } else {
                        let s = sin(2 * Double.pi * t / Theme.shimmerPeriod)
                        dot(opacity: 0.68 + 0.32 * s, haloScale: 1, haloOpacity: 0)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func dot(opacity: Double, haloScale: CGFloat, haloOpacity: Double) -> some View {
        ZStack {
            Circle()
                .fill(status.dotColor.opacity(0.6))
                .scaleEffect(haloScale)
                .opacity(haloOpacity)
            Circle()
                .fill(status.dotColor)
                .opacity(opacity)
        }
        .frame(width: size, height: size)
    }
}
