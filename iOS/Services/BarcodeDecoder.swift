@preconcurrency import Vision
import UIKit

enum BarcodeDecoder {
    struct Decoded: Sendable {
        let value: String
        let type: String
    }

    /// Decodes a barcode from raw image bytes. All UIImage / CGImage work and
    /// the Vision request itself run on a userInitiated background queue —
    /// safe to await from the main actor without blocking gestures.
    static func decode(data: Data) async -> Decoded? {
        await withCheckedContinuation { (cont: CheckedContinuation<Decoded?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = makeCGImage(from: data) else {
                    cont.resume(returning: nil)
                    return
                }

                let request = VNDetectBarcodesRequest { req, _ in
                    let observation = (req.results as? [VNBarcodeObservation])?
                        .first(where: { ($0.payloadStringValue ?? "").isEmpty == false })
                    guard let obs = observation, let value = obs.payloadStringValue else {
                        cont.resume(returning: nil)
                        return
                    }
                    cont.resume(returning: Decoded(value: value, type: mapSymbology(obs.symbology)))
                }
                request.symbologies = [
                    .qr, .code128, .code39, .code93,
                    .ean13, .ean8, .pdf417, .aztec,
                    .upce, .dataMatrix, .itf14
                ]

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do { try handler.perform([request]) }
                catch { cont.resume(returning: nil) }
            }
        }
    }

    private static func makeCGImage(from data: Data) -> CGImage? {
        guard let img = UIImage(data: data) else { return nil }
        if let cg = img.cgImage { return cg }
        let renderer = UIGraphicsImageRenderer(size: img.size)
        return renderer.image { _ in img.draw(at: .zero) }.cgImage
    }

    private static func mapSymbology(_ s: VNBarcodeSymbology) -> String {
        switch s {
        case .qr: return "qr"
        case .code128: return "code128"
        case .pdf417: return "pdf417"
        case .aztec: return "aztec"
        case .ean13: return "ean13"
        case .ean8: return "ean8"
        case .code39: return "code39"
        case .code93: return "code93"
        case .upce: return "upce"
        case .dataMatrix: return "datamatrix"
        case .itf14: return "itf14"
        default: return "unknown"
        }
    }
}
