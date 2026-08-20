import Carbon.HIToolbox
import AppKit

/// Global show/hide shortcut via Carbon's RegisterEventHotKey.
///
/// Deliberately not NSEvent.addGlobalMonitorForEvents: that path requires the user to
/// grant Accessibility/Input Monitoring permission before it fires. Carbon hotkeys are
/// still first-class on modern macOS and need no extra permission, which matters for a
/// small background utility that should just work after install.
final class GlobalHotkey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private static var registry: [UInt32: GlobalHotkey] = [:]
    private static var nextID: UInt32 = 1
    private let id: UInt32

    init?(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        self.action = action
        self.id = GlobalHotkey.nextID
        GlobalHotkey.nextID += 1

        var carbonMods: UInt32 = 0
        if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        if modifiers.contains(.option) { carbonMods |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = UnsafeMutableRawPointer(bitPattern: UInt(id))

        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if let hk = GlobalHotkey.registry[hkID.id] { DispatchQueue.main.async { hk.action() } }
            return noErr
        }, 1, &eventType, selfPtr, &handler)
        guard installStatus == noErr else { return nil }

        var hotKeyID = EventHotKeyID(signature: OSType(0x41564131), id: id) // 'AVA1'
        let status = RegisterEventHotKey(keyCode, carbonMods, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }

        GlobalHotkey.registry[id] = self
    }

    deinit {
        if let r = ref { UnregisterEventHotKey(r) }
        if let h = handler { RemoveEventHandler(h) }
        GlobalHotkey.registry[id] = nil
    }
}
