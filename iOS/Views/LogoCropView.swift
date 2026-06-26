import SwiftUI
import UIKit

struct LogoCropSource: Identifiable, Hashable {
    let id = UUID()
    let data: Data
}

struct LogoCropView: View {
    let source: LogoCropSource
    let onCommit: (Data) -> Void
    let onCancel: () -> Void

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var processing = false

    private let viewportSize: CGFloat = 300
    private let outputSize: CGFloat = 256

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                if let img = image {
                    cropArea(image: img)
                    Text("Drag to position. Pinch to zoom.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Reset") {
                        withAnimation(.spring(duration: 0.25)) {
                            scale = 1.0
                            offset = .zero
                            lastScale = 1.0
                            lastOffset = .zero
                        }
                    }
                    .buttonStyle(.bordered)
                } else {
                    ProgressView().frame(height: viewportSize)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Adjust Logo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                        .disabled(processing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: commit) {
                        if processing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Use logo").bold()
                        }
                    }
                    .disabled(processing || image == nil)
                }
            }
            .task { await loadImage() }
        }
    }

    @ViewBuilder
    private func cropArea(image: UIImage) -> some View {
        ZStack {
            Color.white
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .scaleEffect(scale)
                .offset(offset)
        }
        .frame(width: viewportSize, height: viewportSize)
        .clipShape(Circle())
        .overlay(
            Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1)
        )
        .gesture(
            SimultaneousGesture(
                DragGesture()
                    .onChanged { v in
                        offset = CGSize(
                            width: lastOffset.width + v.translation.width,
                            height: lastOffset.height + v.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    },
                MagnificationGesture()
                    .onChanged { v in
                        scale = min(5.0, max(0.2, lastScale * v))
                    }
                    .onEnded { _ in
                        lastScale = scale
                    }
            )
        )
    }

    private func loadImage() async {
        let data = source.data
        let img = await Task.detached(priority: .userInitiated) {
            UIImage(data: data)
        }.value
        image = img
    }

    private func commit() {
        guard image != nil else { return }
        processing = true
        let data = source.data
        let s = scale
        let o = offset
        let vs = viewportSize
        let os = outputSize
        Task {
            let cropped = await Task.detached(priority: .userInitiated) { () -> Data in
                renderCrop(data: data, scale: s, offset: o, viewportSize: vs, outputSize: os)
            }.value
            await MainActor.run {
                processing = false
                onCommit(cropped)
            }
        }
    }
}

private func renderCrop(
    data: Data,
    scale: CGFloat,
    offset: CGSize,
    viewportSize: CGFloat,
    outputSize: CGFloat
) -> Data {
    guard let img = UIImage(data: data) else { return data }
    let imgSize = img.size
    guard imgSize.width > 0, imgSize.height > 0 else { return data }

    // Match SwiftUI's scaledToFill: smaller dimension fills the viewport.
    let fillScale = max(viewportSize / imgSize.width, viewportSize / imgSize.height)
    let displayedW = imgSize.width * fillScale * scale
    let displayedH = imgSize.height * fillScale * scale

    let outputScale = outputSize / viewportSize
    let drawW = displayedW * outputScale
    let drawH = displayedH * outputScale
    let center = outputSize / 2
    let originX = center - drawW / 2 + offset.width * outputScale
    let originY = center - drawH / 2 + offset.height * outputScale

    let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSize, height: outputSize))
    let result = renderer.image { _ in
        UIColor.white.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: outputSize, height: outputSize))
        img.draw(in: CGRect(x: originX, y: originY, width: drawW, height: drawH))
    }
    return result.jpegData(compressionQuality: 0.85) ?? data
}
