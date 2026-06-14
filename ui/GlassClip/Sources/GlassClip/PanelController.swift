// PanelController.swift — owns the floating NSPanel and wires the hotkey.
//
// Key insight: we use a NON-ACTIVATING panel (.nonactivatingPanel style).
// That means the panel can take keyboard input (because KeyablePanel
// overrides canBecomeKey) WITHOUT stealing focus from the app beneath —
// the app you were typing in stays active. This is what makes it possible
// to paste back into it without re-clicking.

import AppKit
import SwiftUI

/// A borderless panel that accepts keyboard events.
/// NSPanel refuses keystrokes by default when borderless — this override
/// is the one-line fix.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PanelController {
    let model   = HistoryViewModel()
    private var panel: KeyablePanel?
    private var keyMonitor: Any?

    // Hotkey manager lives here so it's alive for the whole session.
    private let hotkey = HotkeyManager()

    private let panelSize = NSSize(width: 400, height: 540)

    // MARK: Lifecycle

    /// Call once from AppDelegate.applicationDidFinishLaunching.
    func start() {
        // Ask for Accessibility on first launch. If denied, paste works
        // everywhere except synthesising the keystroke — the clipboard
        // is still updated, so manual ⌘V always works as a fallback.
        PasteHelper.checkAndPrompt()

        hotkey.onTriggered = { [weak self] in self?.toggle() }
        hotkey.register()
    }

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    // MARK: Show / hide

    func show() {
        let panel = ensurePanel()
        position(panel)

        model.contentVisible = false
        panel.orderFrontRegardless()
        panel.makeKey()

        Task { await model.refresh() }

        // Give SwiftUI one runloop tick to layout in the hidden state,
        // then animate in — otherwise there's nothing to fade FROM.
        DispatchQueue.main.async {
            withAnimation { self.model.contentVisible = true }
        }

        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        withAnimation { model.contentVisible = false }
        // Wait for the 220ms spring animation before pulling the window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.panel?.orderOut(nil)
            self?.model.clearSearch()
        }
    }

    // MARK: Keyboard

    /// Local monitor intercepts keyDown while our panel is key window.
    /// Four keys: ↑ ↓ ⏎ esc. Everything else passes through normally.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, panel.isKeyWindow else {
                return event
            }
            switch event.keyCode {
            case 126: // ↑
                self.model.moveSelection(by: -1); return nil
            case 125: // ↓
                self.model.moveSelection(by: 1);  return nil
            case 36, 76: // Return / numpad Enter
                Task {
                    if await self.model.activateSelection() {
                        self.hide()
                        PasteHelper.pasteAfterDelay() // ← synthesise ⌘V
                    }
                }
                return nil
            case 53: // Esc
                self.hide(); return nil
            default:
                // Type-to-search: any printable character that lands here
                // (because the NSTextField didn't grab focus) is forwarded
                // to the search field by appending to searchText.
                if let char = event.characters,
                   !char.isEmpty,
                   !event.modifierFlags.contains([.command, .control, .option]) {
                    self.model.searchText += char
                    return nil
                }
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    // MARK: Window

    private func ensurePanel() -> KeyablePanel {
        if let panel { return panel }

        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        panel.isFloatingPanel          = true
        panel.level                    = .floating
        panel.isOpaque                 = false
        panel.backgroundColor          = .clear
        panel.hasShadow                = true
        panel.hidesOnDeactivate        = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior       = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = HistoryView(model: model, onActivated: { [weak self] in
            self?.hide()
            PasteHelper.pasteAfterDelay()
        })
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = hosting

        self.panel = panel
        return panel
    }

    /// Positions the panel near the cursor, clamped to visible screen area.
    private func position(_ panel: NSPanel) {
        let mouse  = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
                     ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        var origin = NSPoint(
            x: mouse.x - panelSize.width / 2,
            y: mouse.y - panelSize.height - 8
        )
        origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - panelSize.width - 8))
        if origin.y < visible.minY + 8 { origin.y = mouse.y + 12 }
        panel.setFrameOrigin(origin)
    }
}
