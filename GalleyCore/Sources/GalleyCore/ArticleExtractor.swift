import Foundation
import WebKit

/// Turns a URL into a saved article folder: `article.html`, `meta.json`, `images/`, `qr.png`.
///
/// Pages are loaded in a real (offscreen) WebKit view using Galley's persistent
/// website data store, so sites you have signed into inside Galley arrive signed in.
@MainActor
public final class ArticleExtractor {
    private let paths: GalleyPaths
    private let dataStore: WKWebsiteDataStore

    public var pageTimeout: TimeInterval = 25

    public init(paths: GalleyPaths, dataStore: WKWebsiteDataStore = .default()) {
        self.paths = paths
        self.dataStore = dataStore
    }

    public func extract(url: URL, articleID: UUID) async -> ExtractionOutcome {
        let web = OffscreenWebView(dataStore: dataStore)
        defer { web.close() }
        do {
            try await web.load(url, timeout: pageTimeout)
            try await scrollThrough(web.webView)
            return try await extractLoadedPage(web.webView, requestedURL: url, articleID: articleID)
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }

    /// Scrolls down the page and back so lazy-loaded images and sections load.
    /// Done from Swift because WebKit throttles timers inside hidden windows.
    private func scrollThrough(_ webView: WKWebView) async throws {
        let height = (try? await webView.evaluateJavaScript("document.documentElement.scrollHeight") as? Double) ?? 0
        let step = 1000.0
        var y = 0.0
        while y < min(height, 40000) {
            _ = try? await webView.evaluateJavaScript("window.scrollTo(0, \(y))")
            try await Task.sleep(for: .milliseconds(60))
            y += step
        }
        _ = try? await webView.evaluateJavaScript("window.scrollTo(0, 0)")
        // Give late scripts a moment to put the article and images in place.
        try await Task.sleep(for: .milliseconds(400))
    }

    /// Extracts whatever `webView` is showing right now. Used by the "Fix…" window,
    /// where the reader has signed in or dismissed pop-ups by hand.
    public func extractLoadedPage(_ webView: WKWebView, requestedURL: URL, articleID: UUID) async throws -> ExtractionOutcome {
        let world = WKContentWorld.world(name: "galley")
        _ = try await webView.evaluateJavaScript(try Resources.text("js/readability.js") + "\n;true", in: nil, contentWorld: world)
        let raw = try await webView.callAsyncJavaScript(
            try Resources.text("js/galley-extract.js"),
            arguments: [:],
            in: nil,
            contentWorld: world
        )
        guard let result = raw as? [String: Any] else {
            return .failed(reason: "Galley couldn't read this page.")
        }
        let paywalled = result["paywalled"] as? Bool ?? false
        guard result["ok"] as? Bool == true, let html = result["html"] as? String else {
            let reason = result["reason"] as? String ?? "Couldn't find the article on this page."
            return paywalled ? .needsLogin(nil, reason: "This article is behind a paywall.") : .failed(reason: reason)
        }

        let folder = paths.articleFolder(articleID)
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
        let imagesFolder = folder.appendingPathComponent("images", isDirectory: true)
        try fm.createDirectory(at: imagesFolder, withIntermediateDirectories: true)

        // Download images with the page's cookies, so images on signed-in sites load too.
        let pageURL = webView.url ?? requestedURL
        let cookies = await dataStore.httpCookieStore.allCookies()
        let fetcher = ImageFetcher(cookies: cookies, referer: pageURL, userAgent: OffscreenWebView.userAgent)
        let imageURLs = (result["images"] as? [String] ?? []).map { URL(string: $0) }
        let saved = await fetcher.fetchAll(imageURLs, into: imagesFolder)

        var body = html
        for (index, _) in imageURLs.enumerated().reversed() {
            let replacement = saved[index].map { "images/\($0)" } ?? ""
            body = body.replacingOccurrences(of: "\"galley-img:\(index)\"", with: "\"\(replacement)\"")
        }
        try body.write(to: folder.appendingPathComponent("article.html"), atomically: true, encoding: .utf8)

        // Lead image for the cover and for articles without pictures of their own.
        // Prefer the article's first photo: share images (og:image) often carry the
        // publisher's logo or text baked in.
        var leadFile = saved.sorted(by: { $0.key < $1.key }).first.map { "images/\($0.value)" }
        if leadFile == nil, let leadString = result["leadImage"] as? String, let leadURL = URL(string: leadString),
           let name = await fetcher.fetch(leadURL, into: imagesFolder, baseName: "lead") {
            leadFile = "images/\(name)"
        }

        let canonical = (result["canonicalURL"] as? String).flatMap(URL.init(string:))
        QRCode.write(for: canonical ?? requestedURL, to: folder.appendingPathComponent("qr.png"))

        let wordCount = result["wordCount"] as? Int ?? 0
        let metadata = ArticleMetadata(
            sourceURL: requestedURL,
            canonicalURL: canonical,
            title: (result["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? requestedURL.host() ?? "Untitled",
            byline: Self.cleanByline(result["byline"] as? String),
            siteName: result["siteName"] as? String,
            excerpt: result["excerpt"] as? String,
            publishedAt: (result["publishedTime"] as? String).flatMap(Self.parseDate),
            language: result["lang"] as? String,
            wordCount: wordCount,
            leadImageFile: leadFile,
            bodyHasImages: !saved.isEmpty,
            extractedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata).write(to: folder.appendingPathComponent("meta.json"))

        if paywalled && wordCount < 450 {
            return .needsLogin(metadata, reason: "Only the start of the article is visible. Sign in to \(pageURL.host() ?? "the site") inside Galley.")
        }
        if wordCount < 150 {
            return .needsAttention(metadata, reason: "Only \(wordCount) words found. This may not be the whole article.")
        }
        return .ready(metadata)
    }

    nonisolated public static func loadMetadata(in folder: URL) -> ArticleMetadata? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("meta.json")) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ArticleMetadata.self, from: data)
    }

    nonisolated static func parseDate(_ string: String) -> Date? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: string) { return d }
        full.formatOptions = [.withInternetDateTime]
        if let d = full.date(from: string) { return d }
        full.formatOptions = [.withFullDate]
        return full.date(from: String(string.prefix(10)))
    }

    nonisolated static func cleanByline(_ byline: String?) -> String? {
        guard var b = byline?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty else { return nil }
        if b.lowercased().hasPrefix("by ") { b = String(b.dropFirst(3)) }
        b = b.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return b.count > 120 ? nil : b
    }
}
