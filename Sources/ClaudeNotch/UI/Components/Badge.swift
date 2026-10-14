import SwiftUI

/// Capsule count/label. Tinted when an approval is pending.
@MainActor
struct Badge: View {
    let text: String
    var tinted: Bool = false
    var tint: Color = Theme.approval

    var body: some View {
        Text(text)
            .font(Theme.Typo.micro)
            .tracking(0.2)
            .foregroundStyle(tinted ? tint : Theme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tinted ? tint.opacity(0.2) : Theme.surfaceRaised))
    }
}
