import Foundation

/// Payload written by the Share Extension to the App Group container.
/// The main app reads these on launch, decodes the image as a barcode if
/// possible, creates a Card, and syncs it to the watch.
struct PendingShare: Codable, Sendable {
    let id: UUID
    let createdAt: Date
    let name: String
    let imageData: Data

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
