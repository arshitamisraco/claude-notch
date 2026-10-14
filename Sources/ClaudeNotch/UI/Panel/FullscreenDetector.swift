import AppKit
import CoreGraphics

/// Best-effort detection of "menu bar hidden" (fullscreen app / auto-hide).
enum FullscreenDetector {
    @MainActor
    static func menuBarHidden(on screen: NSScreen) -> Bool {
        // With a visible menu bar, visibleFrame is shorter than the frame.
        if screen.visibleFrame.maxY < screen.frame.maxY - 1 { return false }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
              !list.isEmpty else { return false }
        for window in list {
            let owner = window[kCGWindowOwnerName as String] as? String
            let layer = window[kCGWindowLayer as String] as? Int
            if owner == "Window Server", layer == 24 { return false }
        }
        return true
    }
}
