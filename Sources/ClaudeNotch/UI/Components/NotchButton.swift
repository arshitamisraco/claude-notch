import SwiftUI

enum NotchButtonKind {
    case primary, secondary, dangerGhost, ghost
}

struct NotchPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.fast, value: configuration.isPressed)
    }
}

/// Button per DESIGN: primary / secondary / danger-ghost, 28pt, hint chip, loading + disabled states.
@MainActor
struct NotchButton: View {
    let title: String
    var hint: String? = nil
    var kind: NotchButtonKind = .secondary
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var accessibilityText: String? = nil
    let action: () -> Void

    @State private var hovering = false

    private var foreground: Color {
        switch kind {
        case .primary: return .black
        case .secondary: return Theme.textPrimary
        case .dangerGhost: return Theme.danger
        case .ghost: return Theme.textSecondary
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return hovering ? Color.white : Color.white.opacity(0.9)
        case .secondary: return hovering ? Theme.surfaceHover : Theme.surfaceRaised
        case .dangerGhost: return hovering ? Theme.danger.opacity(0.12) : Color.clear
        case .ghost: return hovering ? Theme.surfaceRaised : Color.clear
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: 6) {
                    Text(title)
                        .font(Theme.Typo.button)
                        .foregroundStyle(foreground)
                        .lineLimit(1)
                    if let hint = hint {
                        KeyHint(text: hint, onLight: kind == .primary)
                    }
                }
                .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous).fill(background)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
        }
        .buttonStyle(NotchPressStyle())
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled ? 0.4 : 1)
        .onHover { inside in
            withAnimation(Theme.fast) { hovering = inside }
        }
        .accessibilityLabel(accessibilityText ?? title)
    }
}
