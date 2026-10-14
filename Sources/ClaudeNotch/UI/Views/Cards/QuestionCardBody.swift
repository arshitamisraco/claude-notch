import SwiftUI

/// Question: option rows (1-4 keys), multiSelect toggles + Submit, multi-question stepper.
@MainActor
struct QuestionCardBody: View {
    let item: NotchItem
    let request: QuestionRequest
    let vm: NotchViewModel

    var body: some View {
        let draft = vm.draft(for: item)
        let count = request.questions.count
        let step = min(draft.step, max(0, count - 1))

        VStack(alignment: .leading, spacing: Theme.Space.sm + 2) {
            if count > 0 {
                let q = request.questions[step]
                if count > 1 {
                    Text("Question \(step + 1) of \(count)")
                        .font(Theme.Typo.micro)
                        .tracking(0.2)
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(q.question)
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: Theme.Space.xs) {
                    ForEach(Array(q.options.enumerated()), id: \.offset) { index, option in
                        OptionRow(
                            index: index,
                            option: option,
                            multiSelect: q.multiSelect,
                            isSelected: (draft.selected[q.question] ?? []).contains(option.label),
                            isEnabled: item.isPending
                        ) { vm.chooseOption(item, index: index) }
                    }
                }

                if item.isPending {
                    HStack(spacing: Theme.Space.sm) {
                        NotchButton(title: "Answer in terminal", kind: .ghost) { vm.handOff(item) }
                            .padding(.leading, -Theme.Space.sm)
                        Spacer(minLength: 0)
                        if q.multiSelect {
                            NotchButton(
                                title: step + 1 >= count ? "Submit" : "Next",
                                hint: "\u{2318}\u{21A9}",
                                kind: .primary,
                                isDisabled: (draft.selected[q.question] ?? []).isEmpty,
                                accessibilityText: "Submit selected answers"
                            ) { vm.submitMulti(item) }
                        }
                    }
                }
            }
        }
    }
}

@MainActor
struct OptionRow: View {
    let index: Int
    let option: QuestionOption
    let multiSelect: Bool
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Theme.Space.sm + 2) {
                leading
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    if let desc = option.description, !desc.isEmpty {
                        Text(desc)
                            .font(Theme.Typo.micro)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(isSelected ? Theme.attention.opacity(0.16) : (hovering ? Theme.surfaceHover : Theme.surfaceRaised))
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        }
        .buttonStyle(NotchPressStyle())
        .disabled(!isEnabled)
        .onHover { inside in
            withAnimation(Theme.fast) { hovering = inside }
        }
        .accessibilityLabel(option.label)
        .accessibilityValue(multiSelect ? (isSelected ? "selected" : "not selected") : "")
    }

    @ViewBuilder
    private var leading: some View {
        if multiSelect {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Theme.attention : Theme.textTertiary)
                .frame(width: 16, height: 16)
        } else if index < 4 {
            Text("\(index + 1)")
                .font(Theme.Typo.micro)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 16, height: 16)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.08)))
        } else {
            Color.clear.frame(width: 16, height: 16)
        }
    }
}
