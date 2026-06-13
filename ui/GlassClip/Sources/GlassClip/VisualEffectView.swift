// VisualEffectView.swift — the real glass.
//
// SwiftUI has no first-class "blur what's BEHIND the window" view on
// macOS, but AppKit does: NSVisualEffectView. NSViewRepresentable is the
// official bridge that lets an AppKit view live inside SwiftUI.
//
// This is the difference between real glassmorphism and fake CSS blur:
// NSVisualEffectView samples the actual pixels behind the window
// (wallpaper, other apps) through the compositor — exactly what Control
// Center and Spotlight use.

import AppKit
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    /// .hudWindow is the dark, high-blur material used by floating
    /// panels; it adapts automatically to light/dark mode.
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        // .behindWindow = blur the desktop/apps behind our window
        // (vs .withinWindow which blurs our own content).
        view.blendingMode = .behindWindow
        // .active = stay frosted even when the window isn't focused.
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
