// Models.swift — Swift mirrors of the Go data model.
//
// The Go daemon sends JSON like:
//   {"id":"…","type":"url","content":"…","preview":"…","timestamp":"2026-06-11T23:44:25.674831+05:30"}
// These types decode exactly that. If you change the Go structs, change
// these to match — this file IS the protocol contract on the Swift side.

import Foundation

/// Mirrors Go's history.ItemType. String raw values match the Go constants.
enum ItemType: String, Codable {
    case text
    case url
    case rich
    case image

    /// SF Symbol name for the row icon.
    var symbolName: String {
        switch self {
        case .text:  return "doc.on.doc"
        case .url:   return "link"
        case .rich:  return "textformat"
        case .image: return "photo"
        }
    }
}

/// Mirrors Go's history.ClipboardItem.
/// Identifiable lets SwiftUI's ForEach track rows by `id`.
struct ClipboardItem: Codable, Identifiable, Equatable {
    let id: String
    let type: ItemType
    let content: String
    let preview: String
    let timestamp: Date
}

/// Mirrors Go's server response. One shape for every command.
struct ServerResponse: Codable {
    let ok: Bool
    let error: String?
    let items: [ClipboardItem]?
}

extension JSONDecoder {
    /// Go marshals time.Time as RFC 3339 with nanoseconds
    /// ("2026-06-11T23:44:25.674831+05:30"). Foundation's built-in
    /// .iso8601 strategy can't parse fractional seconds, so we set up a
    /// formatter that can (with a non-fractional fallback, since Go
    /// omits the fraction when it's exactly zero).
    static func glassClip() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            // The formatters are created inside the closure on purpose:
            // ISO8601DateFormatter is not Sendable (not thread-safe), so
            // sharing one across concurrent decodes is a Swift 6 error.
            // Decoding happens ~once per panel open, so creating two
            // formatters per call costs nothing in practice.
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let withoutFraction = ISO8601DateFormatter()
            withoutFraction.formatOptions = [.withInternetDateTime]
            if let date = withFraction.date(from: value) ?? withoutFraction.date(from: value) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "unparseable timestamp: \(value)"))
        }
        return decoder
    }
}
