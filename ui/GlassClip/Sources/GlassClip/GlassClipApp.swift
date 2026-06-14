// GlassClipApp.swift — the application's entry point.
//
// GlassClip is a menu-bar app (no Dock icon, no app switcher).
// The global ⌘⇧V hotkey is registered at launch via PanelController.start().
// The menu-bar icon provides a backup "Show" option and Quit.

import AppKit
import SwiftUI

@main
struct GlassClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: appDelegate.panelController)
        } label: {
            // SF Symbol that adapts to light/dark menu bar automatically.
            Label("GlassClip", systemImage: "doc.on.clipboard")
        }
    }
}

// MARK: - Menu content

private struct MenuContent: View {
    let controller: PanelController

    var body: some View {
        Button("Show Clipboard History") {
            controller.show()
        }
        .keyboardShortcut("v", modifiers: [.command, .shift])

        Divider()

        Button("Open at Login") { }   // placeholder — Phase 5
            .disabled(true)

        Divider()

        Button("Quit GlassClip") { NSApp.terminate(nil) }
    }
}

// MARK: - App delegate

// @MainActor required because PanelController is @MainActor and we
// instantiate it as a stored property (synchronous construction must
// happen on the same actor as the type's initialiser).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let panelController = PanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // .accessory = menu-bar-only: no Dock icon, no app-switcher entry.
        NSApp.setActivationPolicy(.accessory)

        // Register the Carbon hotkey + check Accessibility permission.
        panelController.start()
    }
}
