import AppKit

/// Notch geometry for one screen, in AppKit global screen coordinates (origin bottom-left).
struct NotchGeometry: Equatable {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    /// Horizontal centre of the notch in global screen coordinates.
    var midX: CGFloat
    var hasNotch: Bool
    var screenFrame: CGRect

    static let fallback = NotchGeometry(
        notchWidth: Theme.Layout.virtualNotch.width,
        notchHeight: Theme.Layout.virtualNotch.height,
        midX: 0,
        hasNotch: false,
        screenFrame: .zero
    )

    @MainActor
    static func make(for screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        let insets = screen.safeAreaInsets
        if insets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = max(0, frame.width - left.width - right.width)
            // Derived from widths so it is correct regardless of the coordinate space of the aux rects.
            let mid = frame.minX + left.width + width / 2
            return NotchGeometry(notchWidth: width, notchHeight: insets.top, midX: mid, hasNotch: true, screenFrame: frame)
        }
        let menuBar = frame.maxY - screen.visibleFrame.maxY
        let height: CGFloat = menuBar > 0 ? menuBar : Theme.Layout.virtualNotch.height
        return NotchGeometry(
            notchWidth: Theme.Layout.virtualNotch.width,
            notchHeight: height,
            midX: frame.midX,
            hasNotch: false,
            screenFrame: frame
        )
    }

    /// Frame of the (fixed-size) panel: top edge flush with the screen top, centred on the notch.
    var panelFrame: CGRect {
        let size = Theme.Layout.panelSize
        return CGRect(x: midX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }
}
