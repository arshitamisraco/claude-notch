import SwiftUI

/// Small keyboard hint chip, e.g. "⌘↩".
@MainActor
struct KeyHint: View {
    let text: String
    var onLight: Bool = false

    var body: some View {
        Text(text)
            .font(Theme.Typo.micro)
            .tracking(0.2)
            .foregroundStyle(onLight ? Color.black.opacity(0.5) : Theme.textTertiary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(onLight ? Color.black.opacity(0.08) : Color.white.opacity(0.08))
            )
            .accessibilityHidden(true)
    }
}
