// PasteHelper.swift — synthesizes a ⌘V keystroke into whatever app had
// focus before our panel appeared.
//
// How paste-injection works:
//   1. The user picks an item in the panel.
//   2. Our daemon puts that item's text back on the macOS clipboard (via
//      pbcopy / the "select" socket command).
//   3. We hide the panel so the previous app regains focus.
//   4. We synthesize a CGEvent ⌘V into that app — it receives it exactly
//      as if the user pressed the keys, and pastes the content.
//
// Why CGEvent (not AppleScript / osascript)?
//   CGEvent is synchronous, low-level, and the same mechanism Karabiner
//   and all serious keyboard tools use. AppleScript is fragile and slow.
//
// Permission required: Accessibility
//   Synthesizing key events into OTHER apps needs the Accessibility
//   entitlement. Without it, the event is silently dropped.
//   checkAndPrompt() opens the System Settings prompt automatically.

import AppKit
import Carbon.HIToolbox
import CoreGraphics

struct PasteHelper {

    /// Fires ⌘V into the frontmost app. Call AFTER hiding the panel and
    /// a short delay so the target app has time to regain key focus.
    ///
    /// The delay is the critical timing detail: if we post the event
    /// before the panel is fully hidden and the previous app is active,
    /// the keypress lands in the wrong window. 150ms is safe in practice.
    static func pasteAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            sendCommandV()
        }
    }

    /// Checks whether Accessibility is granted. If not, opens the
    /// System Settings prompt automatically (the system shows it once
    /// per launch when kAXTrustedCheckOptionPrompt is true).
    @discardableResult
    static func checkAndPrompt() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
            as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: Private

    private static func sendCommandV() {
        guard AXIsProcessTrusted() else {
            // No permission — open settings and show a notification.
            checkAndPrompt()
            showAccessibilityAlert()
            return
        }

        let src = CGEventSource(stateID: .hidSystemState)

        // Key code 9 = V (same as kVK_ANSI_V from Carbon).
        guard
            let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true),
            let up   = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags   = .maskCommand

        // cgAnnotatedSessionEventTap: the event appears to come from the
        // user's session — trusted by most apps including Terminal.
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }

    private static func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "GlassClip needs Accessibility access to paste"
        alert.informativeText =
            "Open System Settings → Privacy & Security → Accessibility and enable GlassClip.\n\nThe settings panel has been opened for you."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
