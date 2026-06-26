import Foundation
import SwiftData

@Model
final class Card {
    @Attribute(.unique) var id: UUID
    var name: String
    var barcodeValue: String?
    var barcodeType: String
    var barcodeImageData: Data?
    var imageData: Data?
    var iconImageData: Data?
    var colorHex: String
    var createdAt: Date

    /// Drives list ordering. Bumped to `.now` whenever the card is opened
    /// (auto-promotes most recently used to the top), and re-assigned to a
    /// midpoint value during drag-to-reorder so the user can override the
    /// "last used" rule for any specific position.
    /// Default `.distantPast` is a sentinel for cards persisted before this
    /// field existed; a one-shot migration on app launch fixes those to
    /// `createdAt`.
    var lastUsedAt: Date = Date.distantPast

    init(
        id: UUID = UUID(),
        name: String,
        barcodeValue: String? = nil,
        barcodeType: String = "qr",
        barcodeImageData: Data? = nil,
        imageData: Data? = nil,
        iconImageData: Data? = nil,
        colorHex: String = "#3B82F6",
        createdAt: Date = .now,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.barcodeValue = barcodeValue
        self.barcodeType = barcodeType
        self.barcodeImageData = barcodeImageData
        self.imageData = imageData
        self.iconImageData = iconImageData
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt ?? createdAt
    }
}
