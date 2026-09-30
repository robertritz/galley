import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum QRCode {
    /// Writes a crisp black-and-white QR code PNG linking to `url`.
    static func write(for url: URL, to destination: URL) {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { return }
        let context = CIContext()
        try? context.writePNGRepresentation(
            of: output,
            to: destination,
            format: .L8,
            colorSpace: CGColorSpace(name: CGColorSpace.linearGray)!
        )
    }
}
