// HistoryView.swift — everything you SEE inside the floating panel.
//
// Layout: header, then up to 10 rows, each with icon + preview +
// relative timestamp, hover highlight, and a selection bar driven by
// the arrow keys. Visual language borrowed from Spotlight/Control
// Center: glass background, 20pt corners, soft shadow.

import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: HistoryViewModel
    /// Called when an item was activated (clicked or Enter) and the
    /// panel should go away. Injected by PanelController.
    var onActivated: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Divider().opacity(0.4)
            if let message = model.errorMessage {
                statusView(symbol: "bolt.slash", title: message,
                           caption: "Start it with:  go run ./cmd/glassclipd")
            } else if model.items.isEmpty {
                statusView(symbol: "clipboard", title: "Nothing here yet",
                           caption: "Copy something and it will show up.")
            } else {
                itemList
            }
        }
        .padding(14)
        .frame(width: 380)
        .background(VisualEffectView()) // ← the real blur
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay( // hairline edge highlight, like Control Center
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        // Entrance/exit animation: fade + scale 95% → 100%, ~180ms.
        .opacity(model.contentVisible ? 1 : 0)
        .scaleEffect(model.contentVisible ? 1 : 0.95, anchor: .top)
        .animation(.easeOut(duration: 0.18), value: model.contentVisible)
    }

    private var header: some View {
        HStack {
            Text("Clipboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("↑↓ navigate · ⏎ paste · esc close")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    private var itemList: some View {
        // ScrollViewReader lets the arrow keys keep the selected row in
        // view, exactly like Spotlight does when you hold ↓.
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        ItemRow(item: item, isSelected: index == model.selectedIndex)
                            .id(index)
                            .onTapGesture {
                                model.selectedIndex = index
                                Task {
                                    if await model.activate(item) { onActivated() }
                                }
                            }
                    }
                }
            }
            .frame(maxHeight: 420)
            .onChange(of: model.selectedIndex) { _, newIndex in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newIndex, anchor: nil)
                }
            }
        }
    }

    private func statusView(symbol: String, title: String, caption: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

/// One row of the history list.
private struct ItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Icon in a soft rounded square, tinted by type.
            Image(systemName: item.type.symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(displayPreview)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text(item.timestamp, format: .relative(presentation: .named))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowBackground)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10)) // whole row clickable
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovered = hovering }
        }
    }

    /// URLs read better without the scheme — show "github.com/x" not
    /// "https://github.com/x" (the full URL is still what gets pasted).
    private var displayPreview: String {
        guard item.type == .url, let url = URL(string: item.content) else {
            return item.preview
        }
        let host = url.host ?? item.preview
        let path = url.path == "/" ? "" : url.path
        return host + path
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.22) }
        if isHovered { return Color.primary.opacity(0.07) }
        return .clear
    }
}
