import SwiftUI

struct WatchCardDetailView: View {
    let card: Card
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var sync: WatchSyncService
    @State private var appeared = false
    @State private var fullscreen = false

    var body: some View {
        Group {
            if let img = displayImage {
                Button {
                    fullscreen = true
                } label: {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(8)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
            } else {
                Text("No code stored")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: appeared)
        .onAppear {
            appeared.toggle()
            // Auto-promote: same rule as iOS, opening counts as using.
            // Bump locally so the watch list reorders immediately, then tell
            // the iPhone so its store agrees and survives the next resync.
            let now = Date.now
            card.lastUsedAt = now
            try? context.save()
            sync.sendCardUsed(id: card.id, at: now)
        }
        .fullScreenCover(isPresented: $fullscreen) {
            FullscreenBarcodeView(image: displayImage)
        }
    }

    private var displayImage: UIImage? {
        if let data = card.barcodeImageData, let img = UIImage(data: data) {
            return img
        }
        if let data = card.imageData, let img = UIImage(data: data) {
            return img
        }
        return nil
    }
}

private struct FullscreenBarcodeView: View {
    let image: UIImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    // Push the code below the area where watchOS draws the
                    // system clock — third-party apps can't hide it, so we
                    // keep the white background full-screen and inset the
                    // image itself to avoid overlap.
                    .padding(.top, 32)
                    .padding([.bottom, .horizontal], 4)
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .onTapGesture {
            dismiss()
        }
    }
}
