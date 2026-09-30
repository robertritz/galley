import Foundation

/// Paper sizes Galley can lay out for. Printing is one-sided for now.
public enum PaperSize: String, Codable, CaseIterable, Sendable, Identifiable {
    case a4
    case letter

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .a4: "A4"
        case .letter: "US Letter"
        }
    }

    /// Value for CSS `@page { size: … }`.
    public var cssSize: String {
        switch self {
        case .a4: "210mm 297mm"
        case .letter: "8.5in 11in"
        }
    }

    /// Size in PostScript points (1/72 inch).
    public var points: CGSize {
        switch self {
        case .a4: CGSize(width: 595.28, height: 841.89)
        case .letter: CGSize(width: 612, height: 792)
        }
    }

    /// US and Canada default to Letter, everyone else to A4.
    public static var regionDefault: PaperSize {
        let region = Locale.current.region?.identifier ?? ""
        return ["US", "CA", "MX", "PH"].contains(region) ? .letter : .a4
    }
}

public enum ImageMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case color
    case grayscale
    case none

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .color: "Colour"
        case .grayscale: "Greyscale"
        case .none: "No images"
        }
    }
}

/// Everything the extractor learned about an article. Written next to the
/// article's HTML as `meta.json` and mirrored into the app's database.
public struct ArticleMetadata: Codable, Sendable, Equatable {
    public var sourceURL: URL
    public var canonicalURL: URL?
    public var title: String
    public var byline: String?
    public var siteName: String?
    public var excerpt: String?
    public var publishedAt: Date?
    public var language: String?
    public var wordCount: Int
    /// File name inside the article folder, e.g. `images/lead.jpg`.
    public var leadImageFile: String?
    /// True when the HTML already contains images, so the opener doesn't need the lead image.
    public var bodyHasImages: Bool
    public var extractedAt: Date

    public var readingMinutes: Int { max(1, Int((Double(wordCount) / 230).rounded())) }
}

/// Outcome of fetching one URL.
public enum ExtractionOutcome: Sendable {
    case ready(ArticleMetadata)
    /// Extraction produced something, but it looks wrong (too short, probably a paywall).
    case needsLogin(ArticleMetadata?, reason: String)
    case needsAttention(ArticleMetadata?, reason: String)
    case failed(reason: String)
}

/// An article as the renderer needs it: plain values, no database types.
public struct RenderArticle: Sendable, Identifiable {
    public var id: UUID
    public var metadata: ArticleMetadata
    public var folder: URL

    public init(id: UUID, metadata: ArticleMetadata, folder: URL) {
        self.id = id
        self.metadata = metadata
        self.folder = folder
    }
}

public struct RenderSettings: Sendable {
    public var paper: PaperSize
    public var imageMode: ImageMode
    public var linkNotes: Bool
    public var themeID: String

    public init(paper: PaperSize = .regionDefault, imageMode: ImageMode = .color, linkNotes: Bool = true, themeID: String = "classic") {
        self.paper = paper
        self.imageMode = imageMode
        self.linkNotes = linkNotes
        self.themeID = themeID
    }
}

/// One edition, ready to lay out.
public struct EditionDocument: Sendable {
    public var masthead: String
    public var number: Int
    public var dateLabel: String
    public var articles: [RenderArticle]
    public var coverArticleID: UUID?
    public var settings: RenderSettings

    public init(masthead: String, number: Int, dateLabel: String, articles: [RenderArticle], coverArticleID: UUID? = nil, settings: RenderSettings) {
        self.masthead = masthead
        self.number = number
        self.dateLabel = dateLabel
        self.articles = articles
        self.coverArticleID = coverArticleID
        self.settings = settings
    }
}

public struct RenderResult: Sendable {
    public var pdfURL: URL
    public var pageCount: Int
    /// First page of each article, keyed by article ID (1-based, as printed).
    public var articleStartPages: [UUID: Int]
}

public struct GalleyError: LocalizedError, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
