// HistoryView.swift — the complete glass panel UI.
//
// Visual language: Apple Intelligence / Control Center / Spotlight.
//   - Real NSVisualEffectView blur (VisualEffectView.swift)
//   - Continuous 20pt rounded corners
//   - Hairline edge stroke (simulates a glass rim)
//   - Accent-coloured selection, soft hover
//   - Search bar that filters live as you type
//   - "2 min. ago" relative timestamps
//   - Keyboard hint footer

import SwiftUI

// MARK: - Root view

struct HistoryView: View {
    @ObservedObject var model: HistoryViewModel
    var onActivated: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            Divider().opacity(0.25).padding(.horizontal, 12)
            content
            footer
        }
        .frame(width: 400)
        .background(VisualEffectView(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            // Glass rim — a subtle light stroke that makes the panel look
            // like frosted glass rather than a flat rectangle.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.25), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 28, x: 0, y: 12)
        // Entrance animation — fade in + scale from 95%.
        .opacity(model.contentVisible ? 1 : 0)
        .scaleEffect(model.contentVisible ? 1 : 0.95, anchor: .top)
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: model.contentVisible)
    }

    // MARK: Sub-views

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Clipboard History")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(model.allItems.count)/10")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.primary.opacity(0.06), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)

            // TextField with no focus ring (we handle keyboard ourselves).
            TextField("Search clipboard…", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onChange(of: model.searchText) { _, _ in
                    model.selectedIndex = 0
                }

            if !model.searchText.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        model.clearSearch()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let message = model.errorMessage {
            statusView(
                symbol: "wifi.slash",
                tint: .orange,
                title: "Daemon not running",
                caption: message + "\n\nStart it:  go run ./cmd/glassclipd"
            )
        } else if model.isLoading {
            ProgressView()
                .controlSize(.small)
                .padding(40)
        } else if model.items.isEmpty && !model.searchText.isEmpty {
            statusView(
                symbol: "magnifyingglass",
                tint: .secondary,
                title: "No results",
                caption: "Nothing in your history matches \"\(model.searchText)\""
            )
        } else if model.items.isEmpty {
            statusView(
                symbol: "clipboard",
                tint: .secondary,
                title: "Nothing here yet",
                caption: "Copy some text, a URL, or a snippet\nand it will appear here instantly."
            )
        } else {
            itemList
        }
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 3) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        ItemRow(
                            item: item,
                            index: index,
                            isSelected: index == model.selectedIndex,
                            searchText: model.searchText
                        )
                        .id(index)
                        .onTapGesture {
                            model.selectedIndex = index
                            Task {
                                if await model.activate(item) { onActivated() }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 400)
            .onChange(of: model.selectedIndex) { _, newIndex in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label("⌘⇧V", systemImage: "keyboard")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.quaternary)
            Spacer()
            Group {
                hintBadge("↑↓", label: "navigate")
                hintBadge("⏎", label: "paste")
                hintBadge("esc", label: "close")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.primary.opacity(0.03))
    }

    private func hintBadge(_ key: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
        }
    }

    private func statusView(symbol: String, tint: Color, title: String, caption: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
    }
}

// MARK: - Item row

private struct ItemRow: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let searchText: String

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            typeIcon
            VStack(alignment: .leading, spacing: 4) {
                previewText
                HStack(spacing: 6) {
                    Text(item.timestamp, format: .relative(presentation: .named))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    if item.type == .url {
                        Text("·")
                            .foregroundStyle(.quaternary)
                        Text("URL")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                    charCount
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovered = hovering }
        }
    }

    // MARK: Pieces

    private var typeIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(iconBackground)
                .frame(width: 30, height: 30)
            Image(systemName: item.type.symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? .white : iconTint)
        }
    }

    /// Shows the preview text with search matches highlighted in accent.
    private var previewText: some View {
        let text = item.type == .url ? cleanURL(item.content) : item.preview

        if !searchText.isEmpty,
           let range = text.range(of: searchText, options: .caseInsensitive) {
            // Highlight the matching substring in accent colour.
            let before   = String(text[..<range.lowerBound])
            let match    = String(text[range])
            let after    = String(text[range.upperBound...])
            return AnyView(
                (Text(before) + Text(match).foregroundColor(.accentColor) + Text(after))
                    .font(.system(size: 12.5))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            )
        }
        return AnyView(
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        )
    }

    @ViewBuilder
    private var charCount: some View {
        if item.type == .text {
            let n = item.content.count
            Text("\(n > 999 ? "\(n/1000)k" : "\(n)") ch")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
    }

    // MARK: Helpers

    private func cleanURL(_ raw: String) -> String {
        guard let url = URL(string: raw) else { return raw }
        let host = url.host ?? raw
        let path = url.path.isEmpty || url.path == "/" ? "" : url.path
        let q    = url.query.map { "?\($0)" } ?? ""
        // Cap at 60 chars to avoid wide panel.
        let full = host + path + q
        return full.count > 60 ? String(full.prefix(57)) + "…" : full
    }

    private var iconTint: Color {
        switch item.type {
        case .url:   return .blue
        case .rich:  return .purple
        case .image: return .green
        case .text:  return .orange
        }
    }

    private var iconBackground: Color {
        if isSelected { return .accentColor }
        return iconTint.opacity(0.15)
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if isHovered  { return Color.primary.opacity(0.07) }
        return .clear
    }
}
