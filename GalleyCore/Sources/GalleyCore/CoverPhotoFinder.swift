import Foundation

/// A photo for the cover when none of the edition's articles has one.
public struct CoverPhoto: Codable, Sendable, Equatable {
    /// Saved image, relative to the edition folder.
    public var file: String
    /// Printed under the photo, e.g. "Photo: Marcin Konsek, CC BY-SA 4.0".
    public var credit: String?
    /// Openverse ID, so asking for another photo doesn't return the same one.
    public var sourceID: String?

    public init(file: String, credit: String?, sourceID: String?) {
        self.file = file
        self.credit = credit
        self.sourceID = sourceID
    }
}

/// Finds openly licensed photos on Openverse (openverse.org), which needs no API key.
public struct CoverPhotoFinder: Sendable {
    public init() {}

    /// Searches for `query` and saves the first usable photo not in `excluding`
    /// as `cover.jpg` in `folder`.
    public func find(query: String, excluding: Set<String> = [], into folder: URL) async -> CoverPhoto? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        var components = URLComponents(string: "https://api.openverse.org/v1/images/")!
        components.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "category", value: "photograph"),
            URLQueryItem(name: "size", value: "large"),
            URLQueryItem(name: "mature", value: "false"),
            URLQueryItem(name: "page_size", value: "20"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue("Galley/0.1 (https://github.com/robertritz/galley)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(SearchResponse.self, from: data)
        else { return nil }

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for result in response.results where !excluding.contains(result.id) {
            guard (result.width ?? 0) >= 1000, let url = URL(string: result.url) else { continue }
            var imageRequest = URLRequest(url: url, timeoutInterval: 20)
            imageRequest.setValue("Galley/0.1 (https://github.com/robertritz/galley)", forHTTPHeaderField: "User-Agent")
            guard let (imageData, _) = try? await URLSession.shared.data(for: imageRequest),
                  let name = ImageFetcher.store(imageData, in: folder, baseName: "cover-\(result.id.prefix(8))")
            else { continue }
            return CoverPhoto(file: name, credit: result.credit, sourceID: result.id)
        }
        return nil
    }

    /// Saves a photo the reader picked (resized for print) into `folder`.
    public static func importPhoto(_ data: Data, into folder: URL) -> CoverPhoto? {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let file = ImageFetcher.store(data, in: folder, baseName: "cover-\(UUID().uuidString.prefix(8))") else { return nil }
        return CoverPhoto(file: file, credit: nil, sourceID: nil)
    }

    /// Words worth searching for in a headline: the longest few that aren't filler.
    public static func keywords(from title: String, limit: Int = 3) -> String {
        let words = title
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count > 3 && !stopWords.contains($0.lowercased()) }
        var seen = Set<String>()
        let unique = words.filter { seen.insert($0.lowercased()).inserted }
        // Prefer capitalised words (places, names) and then longer ones, keeping it short.
        let ranked = unique.sorted { a, b in
            let ca = a.first?.isUppercase == true, cb = b.first?.isUppercase == true
            return ca != cb ? ca : a.count > b.count
        }
        return ranked.prefix(limit).joined(separator: " ")
    }

    static let stopWords: Set<String> = [
        "about", "after", "again", "against", "also", "because", "been", "before", "being", "between",
        "could", "does", "doing", "during", "each", "even", "every", "from", "have", "having", "here",
        "into", "just", "like", "made", "make", "many", "more", "most", "much", "need", "only", "other",
        "over", "says", "should", "some", "such", "than", "that", "their", "them", "then", "there",
        "these", "they", "this", "those", "through", "under", "until", "very", "want", "were", "what",
        "when", "where", "which", "while", "will", "with", "would", "your", "expected", "call", "calls",
    ]

    private struct SearchResponse: Decodable {
        var results: [Result]
    }

    private struct Result: Decodable {
        var id: String
        var url: String
        var width: Int?
        var creator: String?
        var license: String?
        var license_version: String?

        var credit: String? {
            let licence = license.map { l in
                l == "cc0" || l == "pdm" ? "public domain" : "CC \(l.uppercased())" + (license_version.map { " \($0)" } ?? "")
            }
            switch (creator, licence) {
            case let (c?, l?): return "Photo: \(c), \(l)"
            case let (c?, nil): return "Photo: \(c)"
            case let (nil, l?): return "Photo: \(l)"
            default: return nil
            }
        }
    }
}
