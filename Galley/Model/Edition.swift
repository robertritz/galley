import Foundation
import GalleyCore
import SwiftData

enum EditionState: String, Codable {
    /// Being put together; links can be added at any time.
    case draft
    /// Printed. Still editable, and can be moved back to drafts.
    case printed
}

/// An edition is a folder of articles you lay out and print together. Make as many
/// as you like, by topic or by week, whenever you like.
@Model
final class Edition {
    @Attribute(.unique) var id: UUID
    /// Issue number, printed on the cover. Counts up across all editions.
    var number: Int
    /// Optional name, e.g. "Climate" or "Weekend Reading".
    var name: String = ""
    var createdAt: Date = Date.now
    var stateRaw: String
    var coverArticleID: UUID?
    @Relationship(deleteRule: .nullify, inverse: \Article.edition) var articles: [Article]
    var pageCount: Int?
    var renderedAt: Date?
    /// Bumped on every change that affects the layout, so the preview knows it's stale.
    var contentVersion: Int
    var renderedVersion: Int
    /// The settings the current PDF was laid out with (see `Pref.renderKey`).
    var renderedSettings: String = ""
    var printedAt: Date?

    /// Cover photo file in the edition folder: one the reader chose, or one found
    /// online because no article has a picture.
    var coverPhotoFile: String?
    var coverPhotoCredit: String?
    /// True when the reader picked the photo; it then replaces the cover story's own.
    var coverPhotoIsChosen: Bool = false
    /// What the automatic photo was found with, so renaming finds a fitting one.
    var coverPhotoQuery: String?
    /// Openverse IDs already used, so "Find Another" doesn't repeat itself.
    var coverPhotoSeen: [String] = []

    init(number: Int, name: String = "") {
        id = UUID()
        self.number = number
        self.name = name
        createdAt = .now
        stateRaw = EditionState.draft.rawValue
        articles = []
        contentVersion = 1
        renderedVersion = 0
    }

    var state: EditionState {
        get { EditionState(rawValue: stateRaw) ?? .draft }
        set { stateRaw = newValue.rawValue }
    }

    var displayName: String { name.isEmpty ? "No. \(number)" : name }

    /// Printed on the cover: the day it was printed, or today while it's a draft.
    var dateLabel: String {
        (printedAt ?? .now).formatted(date: .long, time: .omitted)
    }

    var orderedArticles: [Article] { articles.sorted { ($0.position, $0.addedAt) < ($1.position, $1.addedAt) } }
    var printableArticles: [Article] { orderedArticles.filter(\.isPrintable) }

    func needsRender(settings: String) -> Bool {
        renderedVersion != contentVersion || renderedSettings != settings
    }

    func touch() { contentVersion += 1 }
}
