// HistoryViewModel.swift — the UI's single source of truth.
//
// @MainActor pins the whole class to the main thread. Swift will give a
// compile error if background code tries to touch these properties —
// thread safety enforced at compile time, not runtime.

import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var allItems: [ClipboardItem] = []
    @Published var searchText: String = ""
    @Published var selectedIndex = 0
    @Published var errorMessage: String?
    @Published var contentVisible = false
    @Published var isLoading = false

    private let client = SocketClient()

    // MARK: Derived state

    /// Items filtered by the search query (case/diacritic-insensitive).
    /// The view always reads this, never allItems directly.
    var items: [ClipboardItem] {
        guard !searchText.isEmpty else { return allItems }
        return allItems.filter {
            $0.content.localizedCaseInsensitiveContains(searchText) ||
            $0.preview.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: Actions

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            allItems = try await client.history()
            selectedIndex = 0
            errorMessage = nil
        } catch {
            allItems = []
            errorMessage = error.localizedDescription
        }
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        // Clamp — no wrap-around, matching Spotlight behaviour.
        selectedIndex = min(max(selectedIndex + delta, 0), items.count - 1)
    }

    /// Puts the item back on the system clipboard via the daemon.
    /// Returns true so the caller can trigger hide + paste.
    func activate(_ item: ClipboardItem) async -> Bool {
        do {
            try await client.select(id: item.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func activateSelection() async -> Bool {
        guard items.indices.contains(selectedIndex) else { return false }
        return await activate(items[selectedIndex])
    }

    func clearSearch() {
        searchText = ""
        selectedIndex = 0
    }
}
