import UIKit

/// Image resize + JPEG encoding helpers. UIImage decoding and re-encoding can
/// take hundreds of milliseconds for large source images, which blocks gestures
/// when run on the main thread (see "System gesture gate timed out" warnings).
/// All call sites should use the async variant or invoke the sync variant from
/// an already-background context (e.g. `NSItemProvider.loadDataRepresentation`).
enum ImageProcessing {
    /// Synchronous — only call from a background thread.
    static func normalize(data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data {
        guard let img = UIImage(data: data) else { return data }
        let resized = img.resized(maxDimension: maxDimension)
        return resized.jpegData(compressionQuality: quality) ?? data
    }

    /// Async — safe to call from the main actor; runs the heavy work on a
    /// detached background task.
    static func normalizeOffMain(data: Data, maxDimension: CGFloat, quality: CGFloat) async -> Data {
        await Task.detached(priority: .userInitiated) {
            normalize(data: data, maxDimension: maxDimension, quality: quality)
        }.value
    }
}
