// GlassClipApp.swift — the app's entry point.
//
// GlassClip has no Dock icon and no normal windows: it lives in the menu
// bar (SwiftUI's MenuBarExtra) and shows the floating panel on demand.
//
// Phase 3: open the panel from the menu bar icon.
// Phase 4 adds the global ⌘⇧V hotkey + paste keystroke.

import AppKit
import SwiftUI

@main
struct GlassClipApp: App {
    // Bridges the old AppKit lifecycle into SwiftUI so we can configure
    // NSApp at launch (activation policy, later the hotkey).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("GlassClip", systemImage: "doc.on.clipboard") {
            Button("Show Clipboard History") {
                appDelegate.panelController.toggle()
            }
            Divider()
            Button("Quit GlassClip") {
                NSApp.terminate(nil)
            }
        }
    }
}

// @MainActor: PanelController is main-actor-isolated, so anything that
// constructs it must be too. AppKit calls delegate methods on the main
// thread anyway — this annotation just tells the compiler that.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let panelController = PanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // .accessory = menu-bar app: no Dock icon, no app switcher entry.
        NSApp.setActivationPolicy(.accessory)
    }
}
