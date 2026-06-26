import SwiftUI

struct CardRowView: View {
    let card: Card

    var body: some View {
        HStack(spacing: 12) {
            iconView
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name).font(.headline)
                if let v = card.barcodeValue, !v.isEmpty {
                    Text(v)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var iconView: some View {
        if let data = card.iconImageData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
        } else {
            Color(hex: card.colorHex)
                .overlay(
                    Image(systemName: fallbackIconName)
                        .foregroundStyle(.white)
                )
        }
    }

    private var fallbackIconName: String {
        if card.barcodeValue != nil { return "qrcode" }
        if card.imageData != nil { return "photo" }
        return "creditcard"
    }
}
