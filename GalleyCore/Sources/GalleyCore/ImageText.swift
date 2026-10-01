import Foundation
import Vision

/// Spots images that are mostly text: promo graphics, screenshots, title cards.
/// They make poor covers ("Join Waitlist" in 80pt), so the cover skips them.
enum ImageText {
    /// True when on-device text recognition finds a lot of text in the image.
    static func isTextHeavy(_ url: URL) -> Bool {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(url: url)
        guard (try? handler.perform([request])) != nil, let lines = request.results else { return false }
        let words = lines.compactMap { $0.topCandidates(1).first?.string }
            .reduce(0) { $0 + $1.split(separator: " ").count }
        let area = lines.reduce(0.0) { $0 + $1.boundingBox.width * $1.boundingBox.height }
        // Measured: promo graphics and screenshots read 19-64 lines and 58+ words; photos,
        // maps and street signs 0-4 short lines.
        return lines.count >= 8 || words >= 15 || area >= 0.12
    }
}
