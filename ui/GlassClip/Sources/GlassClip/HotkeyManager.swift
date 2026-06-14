// HotkeyManager.swift — global ⌘⇧V hotkey via macOS Carbon API.
//
// Why Carbon and not something else?
//   - NSEvent.addGlobalMonitor monitors events but can't INTERCEPT them
//     (the event still reaches other apps).
//   - CGEventTap can intercept, but needs Accessibility permission just
//     for the shortcut — overkill.
//   - Carbon's RegisterEventHotKey is the macOS-blessed way to claim a
//     system-wide shortcut. It's technically "deprecated" but Apple still
//     uses it internally (Spotlight does) and there is no Swift-native
//     replacement as of macOS 26.
//
// How it works:
//   1. We tell the system "when ⌘⇧V is pressed, send an event to MY app".
//   2. We install a C-compatible callback (EventHandlerUPP) that fires.
//   3. The callback receives `userData` — a raw pointer to `self` —
//      which lets us call back into Swift without global state.

import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Called on the main thread whenever ⌘⇧V is pressed anywhere.
    var onTriggered: (() -> Void)?

    func register() {
        // Pass a raw pointer to self into the C callback.
        // passRetained increments the reference count so self isn't
        // deallocated while Carbon holds the pointer.
        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // The callback closure can't capture values (Carbon needs a plain
        // C function pointer), so everything comes in through userData.
        let callback: EventHandlerUPP = { _, _, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            // takeUnretainedValue: we don't want to release here — the
            // manager lives as long as the app.
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData)
                .takeUnretainedValue()
            // Fire on main thread — UI work must happen there.
            DispatchQueue.main.async { manager.onTriggered?() }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            selfPtr,
            &handlerRef
        )

        // "GCv1" is a four-character-code (FourCC) — Carbon's way of
        // namespacing hotkey IDs so different apps don't collide.
        var hotKeyID = EventHotKeyID(signature: fourCC("GCv1"), id: 1)

        RegisterEventHotKey(
            UInt32(kVK_ANSI_V),          // the V key
            UInt32(cmdKey | shiftKey),   // ⌘ + ⇧ modifiers
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(0),
            &hotKeyRef
        )
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        // Balance the passRetained above.
        Unmanaged.passUnretained(self).release()
    }
}

/// Converts a 4-character ASCII string into a Carbon FourCC OSType.
private func fourCC(_ s: String) -> OSType {
    s.utf8.prefix(4).reduce(0) { ($0 << 8) | OSType($1) }
}
