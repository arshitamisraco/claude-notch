import AppKit
import SwiftUI

/// Borderless, non-activating panel that sits over the notch.
/// Only becomes key while expanded so keyboard shortcuts work without activating the app.
final class NotchPanel: NSPanel {
    var allowsKey: Bool = false
    /// Return true if the key event was consumed.
    var keyHandler: ((NSEvent) -> Bool)?

    init() {
        super.init(
            contentRect: CGRect(origin: .zero, size: Theme.Layout.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = true
        appearance = NSAppearance(named: .darkAqua)
    }

    /// AppKit normally pushes windows below the menu bar; the notch panel must overlap it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, allowsKey, let handler = keyHandler, handler(event) {
            return
        }
        super.sendEvent(event)
    }
}

/// Hosting view that ignores the notch safe area, so SwiftUI content starts at the very top of the screen.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }
}
