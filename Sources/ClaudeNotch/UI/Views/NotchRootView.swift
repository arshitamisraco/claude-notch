import SwiftUI

struct InteractiveRectKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Root of the panel: a fixed transparent canvas with the notch pill anchored top-centre.
@MainActor
struct NotchRootView: View {
    let vm: NotchViewModel

    @State private var contentHeight: CGFloat = 220
    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnv

    private var reduceMotion: Bool { reduceMotionEnv || vm.reduceMotion }

    var body: some View {
        let mode = vm.mode
        let fillet = vm.fillet
        let bodyWidth = width(for: mode)
        let totalWidth = bodyWidth + 2 * fillet
        let height = height(for: mode)
        let bottom = mode == .expanded ? Theme.Radius.notchBottomExpanded : Theme.Radius.notchBottomCollapsed
        let shape = AnyShape(NotchShape(topFillet: fillet, bottomRadius: bottom))
        let hidden = mode == .idle && (!vm.geometry.hasNotch || vm.floating)

        ZStack(alignment: .top) {
            content(for: mode)
                .padding(.horizontal, fillet)
                .frame(width: totalWidth, height: height, alignment: .top)
                .clipShape(shape)
                .background(
                    shape
                        .fill(Theme.surface)
                        .shadow(color: Color.black.opacity(mode == .expanded ? 0.5 : 0), radius: 24, x: 0, y: 8)
                )
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: InteractiveRectKey.self,
                            value: proxy.frame(in: .named("notchRoot"))
                        )
                    }
                )
                .opacity(hidden ? 0 : 1)
                .padding(.top, vm.floating ? 8 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: "notchRoot")
        .animation(Theme.animation(for: mode, reduceMotion: reduceMotion), value: mode)
        .animation(Theme.animation(for: mode, reduceMotion: reduceMotion), value: vm.floating)
        .animation(Theme.animation(for: mode, reduceMotion: reduceMotion), value: height)
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
        .onPreferenceChange(InteractiveRectKey.self) { rect in
            vm.interactiveRect = rect
            vm.onInteractiveRectChange?()
        }
        .onPreferenceChange(ContentHeightKey.self) { h in
            if h > 0 { contentHeight = h }
        }
        .onChange(of: vm.store.latestArrival) { _, _ in
            vm.handleArrival()
        }
        .onChange(of: vm.mode) { _, _ in
            vm.modeDidChange()
        }
    }

    // MARK: Sizing

    private func width(for mode: NotchMode) -> CGFloat {
        switch mode {
        case .idle: return vm.layoutNotchWidth
        case .glance: return vm.layoutNotchWidth + 2 * Theme.Layout.earWidth
        case .peek: return Theme.Layout.peekWidth
        case .expanded: return Theme.Layout.expandedWidth
        }
    }

    private func height(for mode: NotchMode) -> CGFloat {
        let h = vm.layoutNotchHeight
        switch mode {
        case .idle, .glance: return h
        case .peek: return h + Theme.Layout.peekExtraHeight
        case .expanded:
            return min(Theme.Layout.expandedMaxHeight, max(contentHeight, h + 48))
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(for mode: NotchMode) -> some View {
        switch mode {
        case .idle:
            Color.clear
        case .glance:
            GlanceEarsView(vm: vm)
                .transition(.opacity)
        case .peek:
            VStack(spacing: 0) {
                Color.clear.frame(height: vm.layoutNotchHeight)
                if let item = vm.peekItem {
                    PeekView(vm: vm, item: item)
                }
            }
            .transition(.opacity)
        case .expanded:
            ScrollView(.vertical, showsIndicators: false) {
                ExpandedView(vm: vm)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                        }
                    )
            }
            .scrollBounceBehavior(.basedOnSize)
            .transition(.opacity)
        }
    }
}
