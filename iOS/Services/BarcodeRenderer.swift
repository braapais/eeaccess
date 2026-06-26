import UIKit
import CoreImage.CIFilterBuiltins

enum BarcodeRenderer {
    static let renderableTypes: Set<String> = ["qr", "code128", "pdf417", "aztec"]

    static func canRender(type: String) -> Bool {
        renderableTypes.contains(type.lowercased())
    }

    static func render(value: String, type: String, size: CGSize) -> UIImage? {
        let context = CIContext()
        let data = Data(value.utf8)
        let output: CIImage?

        switch type.lowercased() {
        case "qr":
            let f = CIFilter.qrCodeGenerator()
            f.message = data
            f.correctionLevel = "M"
            output = f.outputImage
        case "code128":
            let f = CIFilter.code128BarcodeGenerator()
            f.message = data
            f.quietSpace = 7
            output = f.outputImage
        case "pdf417":
            let f = CIFilter.pdf417BarcodeGenerator()
            f.message = data
            output = f.outputImage
        case "aztec":
            let f = CIFilter.aztecCodeGenerator()
            f.message = data
            output = f.outputImage
        default:
            return nil
        }

        guard let ci = output else { return nil }
        let scaleX = size.width / ci.extent.width
        let scaleY = size.height / ci.extent.height
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
