import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downloads article images and stores print-ready copies: at most 2000 px on the
/// long side (about 300 dpi at full page width), JPEG or PNG, no icons or tracking pixels.
struct ImageFetcher: Sendable {
    private let session: URLSession
    private let referer: URL
    private let userAgent: String

    static let maxPixelSize = 2000
    static let minPixelSize = 120

    init(cookies: [HTTPCookie], referer: URL, userAgent: String) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        let storage = HTTPCookieStorage()
        for cookie in cookies { storage.setCookie(cookie) }
        config.httpCookieStorage = storage
        session = URLSession(configuration: config)
        self.referer = referer
        self.userAgent = userAgent
    }

    /// Returns image index → saved file name. Failed or skipped images are missing.
    func fetchAll(_ urls: [URL?], into folder: URL) async -> [Int: String] {
        await withTaskGroup(of: (Int, String?).self) { group in
            var results: [Int: String] = [:]
            var next = 0
            let limit = 6
            func addNext() {
                guard next < urls.count else { return }
                let index = next
                next += 1
                group.addTask {
                    guard let url = urls[index] else { return (index, nil) }
                    return (index, await fetch(url, into: folder, baseName: String(format: "%03d", index)))
                }
            }
            for _ in 0..<limit { addNext() }
            for await (index, name) in group {
                if let name { results[index] = name }
                addNext()
            }
            return results
        }
    }

    func fetch(_ url: URL, into folder: URL, baseName: String) async -> String? {
        guard url.scheme == "http" || url.scheme == "https" else { return nil }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("image/avif,image/webp,image/png,image/jpeg,image/*;q=0.8", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode ?? 200 < 400
        else { return nil }
        return Self.store(data, in: folder, baseName: baseName)
    }

    static func store(_ data: Data, in folder: URL, baseName: String) -> String? {
        if looksLikeSVG(data) {
            let name = "\(baseName).svg"
            return (try? data.write(to: folder.appendingPathComponent(name))) != nil ? name : nil
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard max(width, height) >= minPixelSize else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let type = hasAlpha ? UTType.png : UTType.jpeg
        let name = "\(baseName).\(hasAlpha ? "png" : "jpg")"
        let url = folder.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? name : nil
    }

    private static func looksLikeSVG(_ data: Data) -> Bool {
        guard let head = String(data: data.prefix(512), encoding: .utf8)?.lowercased() else { return false }
        return head.contains("<svg")
    }
}
