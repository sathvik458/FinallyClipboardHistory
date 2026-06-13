// PanelController.swift — owns the floating window.
//
// SwiftUI draws the content, but the WINDOW itself is AppKit: we need a
// borderless, floating, non-activating panel that appears near the
// cursor — none of which SwiftUI's WindowGroup can do. This is the
// standard split for Spotlight-style apps: AppKit for the window shell,
// SwiftUI for everything inside it.

import AppKit
import SwiftUI

/// NSPanel refuses keyboard focus when it's borderless, by default.
/// Overriding canBecomeKey lets our panel receive arrow keys / Enter.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PanelController {
    let model = HistoryViewModel()
    private var panel: KeyablePanel?
    private var keyMonitor: Any?

    private let panelSize = NSSize(width: 380, height: 520)

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = ensurePanel()
        position(panel)

        // Start invisible, then flip contentVisible — SwiftUI animates
        // the fade-in + 95%→100% scale (see HistoryView).
        model.contentVisible = false
        panel.orderFrontRegardless()
        panel.makeKey()

        Task { await model.refresh() }

        // Flip on the next runloop turn so the first frame really
        // renders in the hidden state (otherwise there's nothing to
        // animate FROM).
        DispatchQueue.main.async { self.model.contentVisible = true }

        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        model.contentVisible = false // animates the fade-out
        // Take the window off screen after the 180ms animation finishes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
            self?.panel?.orderOut(nil)
        }
    }

    // MARK: Window construction

    private func ensurePanel() -> KeyablePanel {
        if let panel { return panel }

        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            // .borderless: no title bar — our rounded glass IS the window.
            // .nonactivatingPanel: the panel can take keystrokes WITHOUT
            // activating our app, so the app you were typing in keeps
            // focus underneath. That's what makes paste-into-it possible.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating                  // above normal windows
        panel.isOpaque = false
        panel.backgroundColor = .clear           // window is a clear canvas;
                                                 // the glass comes from
                                                 // NSVisualEffectView inside
        panel.hasShadow = true                   // soft system shadow
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true // drag anywhere to move
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Host the SwiftUI content. onActivated → hide the panel after
        // an item is chosen.
        let root = HistoryView(model: model, onActivated: { [weak self] in
            self?.hide()
        })
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = hosting

        self.panel = panel
        return panel
    }

    /// Places the panel near the mouse cursor (like a context menu),
    /// clamped so it never hangs off the screen edge.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation // global coords, origin bottom-left
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        var origin = NSPoint(
            x: mouse.x - panelSize.width / 2,  // centered on the cursor
            y: mouse.y - panelSize.height - 12 // panel below the cursor
        )
        // Clamp inside the visible area (respects Dock and menu bar).
        origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - panelSize.width - 8))
        if origin.y < visible.minY + 8 {
            origin.y = mouse.y + 12 // not enough room below → open upward
        }
        panel.setFrameOrigin(origin)
    }

    // MARK: Keyboard handling

    /// A local event monitor sees every keyDown headed for OUR app and
    /// may swallow it (return nil) or pass it on. We use it instead of
    /// SwiftUI focus plumbing because it's reliable in a borderless
    /// panel and trivial to reason about — exactly four keys.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, panel.isKeyWindow else {
                return event // panel not focused → not our business
            }
            switch event.keyCode {
            case 126: // ↑
                self.model.moveSelection(by: -1)
                return nil // swallow: we handled it
            case 125: // ↓
                self.model.moveSelection(by: 1)
                return nil
            case 36, 76: // Return / keypad Enter
                Task {
                    if await self.model.activateSelection() { self.hide() }
                }
                return nil
            case 53: // Escape
                self.hide()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
