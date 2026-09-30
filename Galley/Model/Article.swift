import Foundation
import GalleyCore
import SwiftData

enum ArticleStatus: String, Codable {
    case queued
    case fetching
    case ready
    case needsLogin
    case needsAttention
    case failed

    var isProblem: Bool { [.needsLogin, .needsAttention, .failed].contains(self) }
    var isWorking: Bool { self == .queued || self == .fetching }

    var label: String {
        switch self {
        case .queued: "Waiting"
        case .fetching: "Fetching…"
        case .ready: "Ready"
        case .needsLogin: "Needs login"
        case .needsAttention: "Needs attention"
        case .failed: "Failed"
        }
    }
}

@Model
final class Article {
    @Attribute(.unique) var id: UUID
    var sourceURL: URL
    var title: String
    var byline: String?
    var siteName: String?
    var excerpt: String?
    var publishedAt: Date?
    var wordCount: Int
    var leadImageFile: String?
    var statusRaw: String
    var failureReason: String?
    var addedAt: Date
    /// Order inside the edition.
    var position: Int
    /// First page in the most recent render of its edition.
    var startPage: Int?
    var edition: Edition?

    init(url: URL, position: Int) {
        id = UUID()
        sourceURL = url
        title = url.host() ?? url.absoluteString
        wordCount = 0
        statusRaw = ArticleStatus.queued.rawValue
        addedAt = .now
        self.position = position
    }

    var status: ArticleStatus {
        get { ArticleStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    /// Only articles with extracted content go into the printed edition.
    var isPrintable: Bool {
        status == .ready || ((status == .needsAttention || status == .needsLogin) && wordCount > 0)
    }

    var displaySite: String { siteName ?? sourceURL.host()?.replacingOccurrences(of: "www.", with: "") ?? "" }

    var readingMinutes: Int { max(1, Int((Double(wordCount) / 230).rounded())) }

    func apply(_ metadata: ArticleMetadata) {
        title = metadata.title
        byline = metadata.byline
        siteName = metadata.siteName
        excerpt = metadata.excerpt
        publishedAt = metadata.publishedAt
        wordCount = metadata.wordCount
        leadImageFile = metadata.leadImageFile
    }
}
