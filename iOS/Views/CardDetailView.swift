import SwiftUI
import SwiftData

struct CardDetailView: View {
    let card: Card
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var sync: PhoneSyncService
    @State private var showingEdit = false
    @State private var showingFullscreen = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let barcode = barcodeImage {
                    Button {
                        showingFullscreen = true
                    } label: {
                        Image(uiImage: barcode)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .padding(40)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }

                if let data = card.imageData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if let v = card.barcodeValue {
                    Text(v)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if barcodeImage != nil {
                    Text("Tap the code to enlarge for scanning")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddCardView(editingCard: card)
        }
        .fullScreenCover(isPresented: $showingFullscreen) {
            FullscreenBarcodeView(image: barcodeImage)
        }
        .onAppear {
            // Auto-promote the card to the top of the list — opening it
            // counts as "using" it.
            card.lastUsedAt = .now
            try? context.save()
            sync.sendUpsert(card: card)
        }
    }

    private var barcodeImage: UIImage? {
        if let data = card.barcodeImageData, let img = UIImage(data: data) {
            return img
        }
        guard let value = card.barcodeValue else { return nil }
        return BarcodeRenderer.render(
            value: value,
            type: card.barcodeType,
            size: barcodeRenderSize(for: card.barcodeType)
        )
    }

    private func barcodeRenderSize(for type: String) -> CGSize {
        switch type.lowercased() {
        case "qr", "aztec": return CGSize(width: 600, height: 600)
        default: return CGSize(width: 800, height: 240)
        }
    }
}

private struct FullscreenBarcodeView: View {
    let image: UIImage?
    @Environment(\.dismiss) private var dismiss
    @State private var previousBrightness: CGFloat = 0.5

    /// `UIScreen.main` is deprecated in iOS 26 — pull the screen out of the
    /// foreground-active window scene instead.
    private var activeScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(8)
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .onTapGesture {
            dismiss()
        }
        .onAppear {
            if let screen = activeScreen {
                previousBrightness = screen.brightness
                screen.brightness = 1.0
            }
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            activeScreen?.brightness = previousBrightness
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
