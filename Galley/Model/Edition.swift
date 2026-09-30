import Foundation
import GalleyCore
import SwiftData

enum EditionState: String, Codable {
    /// Collecting new articles.
    case open
    /// Period is over; laid out and ready to print. Still editable.
    case closed
    case printed
}

@Model
final class Edition {
    @Attribute(.unique) var id: UUID
    var number: Int
    var periodStart: Date
    /// When the edition closes automatically. Nil for manual cadence.
    var periodEnd: Date?
    var stateRaw: String
    var coverArticleID: UUID?
    @Relationship(deleteRule: .nullify, inverse: \Article.edition) var articles: [Article]
    var dateLabel: String
    var pageCount: Int?
    var renderedAt: Date?
    /// Bumped on every change that affects the layout, so the preview knows it's stale.
    var contentVersion: Int
    var renderedVersion: Int
    /// The settings the current PDF was laid out with (see `Pref.renderKey`).
    var renderedSettings: String = ""
    var closedAt: Date?
    var printedAt: Date?

    init(number: Int, periodStart: Date, periodEnd: Date?, dateLabel: String) {
        id = UUID()
        self.number = number
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        stateRaw = EditionState.open.rawValue
        articles = []
        self.dateLabel = dateLabel
        contentVersion = 1
        renderedVersion = 0
    }

    var state: EditionState {
        get { EditionState(rawValue: stateRaw) ?? .closed }
        set { stateRaw = newValue.rawValue }
    }

    var orderedArticles: [Article] { articles.sorted { ($0.position, $0.addedAt) < ($1.position, $1.addedAt) } }
    var printableArticles: [Article] { orderedArticles.filter(\.isPrintable) }

    var title: String { "No. \(number)" }

    func needsRender(settings: String) -> Bool {
        renderedVersion != contentVersion || renderedSettings != settings
    }

    func touch() { contentVersion += 1 }
}
