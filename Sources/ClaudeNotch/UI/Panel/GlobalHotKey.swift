import AppKit
import Carbon.HIToolbox

/// Carbon global hot key (⌃⌥C). Needs no Accessibility permission.
final class GlobalHotKey {
    private static var handlers: [UInt32: @MainActor () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var eventHandlerInstalled = false

    private var hotKeyRef: EventHotKeyRef?
    private var id: UInt32 = 0

    /// Registers the hot key; returns nil if registration fails.
    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping @MainActor () -> Void) {
        GlobalHotKey.installEventHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: OSType(0x434E5448), id: GlobalHotKey.nextID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let registered = ref else { return nil }
        self.hotKeyRef = registered
        self.id = GlobalHotKey.nextID
        GlobalHotKey.handlers[self.id] = handler
        GlobalHotKey.nextID += 1
    }

    /// ⌃⌥C
    static func toggleHotKey(handler: @escaping @MainActor () -> Void) -> GlobalHotKey? {
        return GlobalHotKey(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey), handler: handler)
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        GlobalHotKey.handlers[id] = nil
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        GlobalHotKey.handlers[id] = nil
    }

    fileprivate static func fire(id: UInt32) {
        Task { @MainActor in
            GlobalHotKey.handlers[id]?()
        }
    }

    private static func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // Non-capturing closure -> convertible to the C function pointer EventHandlerUPP.
        let callback: EventHandlerUPP = { _, event, _ in
            guard let event = event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr {
                GlobalHotKey.fire(id: hotKeyID.id)
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }
        let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, nil)
        if status == noErr { eventHandlerInstalled = true }
    }
}
