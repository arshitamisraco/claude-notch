import SwiftUI

/// Monospaced, selectable block. Two lines collapsed with "Show more"; horizontal scroll.
struct CodeBlock: View {
    let text: String
    var collapsedLines: Int = 2

    @State private var showAll = false

    private var needsToggle: Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return lines > collapsedLines || text.count > 140
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(showAll ? [.horizontal, .vertical] : [.horizontal], showsIndicators: false) {
                Text(text)
                    .font(Theme.Typo.code)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(showAll ? nil : collapsedLines)
                    .fixedSize(horizontal: true, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, Theme.Space.sm + 2)
                    .padding(.vertical, Theme.Space.sm)
                    .frame(minWidth: 0, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: showAll ? 160 : nil, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.surfaceRaised)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))

            if needsToggle {
                Button(showAll ? "Show less" : "Show more") {
                    withAnimation(Theme.fast) { showAll.toggle() }
                }
                .buttonStyle(.plain)
                .font(Theme.Typo.micro)
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 2)
            }
        }
    }
}
