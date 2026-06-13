// HistoryViewModel.swift — the UI's single source of truth.
//
// SwiftUI is declarative: views are a function of state. This class IS
// that state. @Published properties automatically re-render any view
// that reads them when they change.
//
// @MainActor pins every property and method to the main thread — UI
// state must only change there. Swift enforces it at compile time.

import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var selectedIndex = 0
    @Published var errorMessage: String?
    /// Drives the fade/scale animation; PanelController flips it.
    @Published var contentVisible = false

    private let client = SocketClient()

    /// Pulls fresh history from the daemon. Called every time the panel
    /// opens, so the list is always current.
    func refresh() async {
        do {
            items = try await client.history()
            selectedIndex = 0
            errorMessage = nil
        } catch {
            items = []
            errorMessage = error.localizedDescription
        }
    }

    /// Arrow-key movement, clamped to the list bounds (Spotlight-style:
    /// no wrap-around).
    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), items.count - 1)
    }

    /// Asks the daemon to put the given item back on the clipboard.
    /// Returns true on success so the caller knows it may dismiss the
    /// panel (and, in Phase 4, fire the paste keystroke).
    func activate(_ item: ClipboardItem) async -> Bool {
        do {
            try await client.select(id: item.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Keyboard path: activate whatever the selection bar is on.
    func activateSelection() async -> Bool {
        guard items.indices.contains(selectedIndex) else { return false }
        return await activate(items[selectedIndex])
    }
}
