import Foundation

struct CardPayload: Codable, Hashable {
    let id: UUID
    let name: String
    let barcodeValue: String?
    let barcodeType: String
    let barcodeImageData: Data?
    let imageData: Data?
    let iconImageData: Data?
    let colorHex: String
    let createdAt: Date
    let lastUsedAt: Date?

    init(card: Card) {
        self.id = card.id
        self.name = card.name
        self.barcodeValue = card.barcodeValue
        self.barcodeType = card.barcodeType
        self.barcodeImageData = card.barcodeImageData
        self.imageData = card.imageData
        self.iconImageData = card.iconImageData
        self.colorHex = card.colorHex
        self.createdAt = card.createdAt
        self.lastUsedAt = card.lastUsedAt
    }

    func encode() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(self)
    }

    static func decode(from data: Data) -> CardPayload? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CardPayload.self, from: data)
    }
}
