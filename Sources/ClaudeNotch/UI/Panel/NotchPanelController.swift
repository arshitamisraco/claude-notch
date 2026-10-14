import AppKit
import SwiftUI

/// Owns the NotchPanel, mouse monitors (click-through), hot key, and screen observers.
@MainActor
final class NotchPanelController {
    private let store: NotchStore
    private let settings: UISettings
    private let viewModel: NotchViewModel

    private var panel: NotchPanel?
    private var hotKey: GlobalHotKey?
    private var globalMoveMonitor: Any?
    private var localMoveMonitor: Any?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var floatingCheckTask: Task<Void, Never>?
    private var currentScreen: NSScreen?

    init(store: NotchStore, settings: UISettings) {
        self.store = store
        self.settings = settings
        self.viewModel = NotchViewModel(store: store, settings: settings)

        viewModel.onModeChange = { [weak self] mode in
            self?.applyMode(mode)
        }
        viewModel.onInteractiveRectChange = { [weak self] in
            self?.updatePointerState()
        }
        viewModel.onArrival = { [weak self] in
            self?.arrivalOccurred()
        }
        store.addArrivalObserver { item in
            Announcer.announce(item: item)
        }
    }

    // MARK: Public API

    func show() {
        if panel == nil { buildPanel() }
        guard let panel = panel else { return }
        repositionPanel()
        panel.orderFrontRegardless()
        installMonitors()
        installObservers()
        registerHotKey()
        updatePointerState()
    }

    func hide() {
        panel?.orderOut(nil)
        removeMonitors()
        removeObservers()
        hotKey?.unregister()
        hotKey = nil
        floatingCheckTask?.cancel()
    }

    func toggleExpanded() {
        viewModel.togglePinned()
    }

    func settingsDidChange() {
        repositionPanel()
        registerHotKey()
    }

    // MARK: Panel

    private func buildPanel() {
        let panel = NotchPanel()
        panel.keyHandler = { [weak self] event in
            guard let self = self else { return false }
            return MainActor.assumeIsolated { self.viewModel.handleKey(event) }
        }
        let root = NotchRootView(vm: viewModel)
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: Theme.Layout.panelSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.panel = panel
    }

    private func applyMode(_ mode: NotchMode) {
        guard let panel = panel else { return }
        if mode == .expanded {
            panel.allowsKey = true
            panel.makeKey()
        } else {
            panel.allowsKey = false
            if panel.isKeyWindow { panel.resignKey() }
        }
        updatePointerState()
    }

    private func arrivalOccurred() {
        if settings.displayPreference == .mouse {
            repositionPanel()
        }
        scheduleFloatingCheck()
    }

    // MARK: Screen selection / geometry

    private func pickScreen() -> NSScreen? {
        switch settings.displayPreference {
        case .builtIn:
            if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) { return notched }
            return NSScreen.main ?? NSScreen.screens.first
        case .main:
            return NSScreen.main ?? NSScreen.screens.first
        case .mouse:
            let mouse = NSEvent.mouseLocation
            if let s = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) { return s }
            return NSScreen.main ?? NSScreen.screens.first
        }
    }

    private func repositionPanel() {
        guard let panel = panel, let screen = pickScreen() else { return }
        currentScreen = screen
        let geometry = NotchGeometry.make(for: screen)
        viewModel.geometry = geometry
        panel.setFrame(geometry.panelFrame, display: false)
        updateFloating()
        updatePointerState()
    }

    private func updateFloating() {
        guard let screen = currentScreen else { return }
        let hidden = FullscreenDetector.menuBarHidden(on: screen)
        if viewModel.floating != hidden { viewModel.floating = hidden }
    }

    private func scheduleFloatingCheck() {
        floatingCheckTask?.cancel()
        floatingCheckTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.updateFloating()
        }
    }

    // MARK: Click-through / hover

    private func installMonitors() {
        removeMonitors()
        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointerState() }
        }
        localMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.updatePointerState() }
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedOutside() }
        }
    }

    private func removeMonitors() {
        if let m = globalMoveMonitor { NSEvent.removeMonitor(m) }
        if let m = localMoveMonitor { NSEvent.removeMonitor(m) }
        if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
        if let m = localClickMonitor { NSEvent.removeMonitor(m) }
        globalMoveMonitor = nil
        localMoveMonitor = nil
        globalClickMonitor = nil
        localClickMonitor = nil
    }

    private func pointerIsInside() -> Bool {
        guard let panel = panel else { return false }
        let loc = NSEvent.mouseLocation
        let frame = panel.frame
        let local = CGPoint(x: loc.x - frame.minX, y: frame.maxY - loc.y)
        let slop = Theme.Layout.hitSlop
        return viewModel.interactiveRect.insetBy(dx: -slop, dy: -slop).contains(local)
    }

    private func updatePointerState() {
        guard let panel = panel else { return }
        let inside = pointerIsInside()
        let shouldIgnore = !inside
        if panel.ignoresMouseEvents != shouldIgnore { panel.ignoresMouseEvents = shouldIgnore }
        viewModel.pointerChanged(inside: inside)
    }

    private func clickedOutside() {
        // Global monitors only see events delivered to other apps, i.e. clicks outside the panel.
        if viewModel.pinnedExpanded && !pointerIsInside() {
            viewModel.collapse()
        }
    }

    // MARK: Hot key

    private func registerHotKey() {
        hotKey?.unregister()
        hotKey = nil
        guard settings.globalHotKeyEnabled else { return }
        hotKey = GlobalHotKey.toggleHotKey { [weak self] in
            self?.toggleExpanded()
        }
    }

    // MARK: Observers

    private func installObservers() {
        removeObservers()
        let nc = NotificationCenter.default
        let wc = NSWorkspace.shared.notificationCenter

        add(nc, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.repositionPanel()
        }
        add(wc, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in
            self?.repositionPanel()
            self?.scheduleFloatingCheck()
        }
        add(wc, NSWorkspace.didActivateApplicationNotification) { [weak self] in
            self?.scheduleFloatingCheck()
        }
    }

    private func add(_ center: NotificationCenter, _ name: Notification.Name, _ block: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in block() }
        }
        observers.append((center: center, token: token))
    }

    private func removeObservers() {
        for entry in observers { entry.center.removeObserver(entry.token) }
        observers.removeAll()
    }
}
