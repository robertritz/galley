import AppKit
import Foundation
import GalleyCore
import Observation
import SwiftData
import WebKit

/// Owns the app's behaviour: editions, adding links, fetching articles, and
/// laying editions out as PDFs.
@Observable
final class Library {
    let paths = GalleyPaths.default
    private(set) var context: ModelContext!
    private var extractor: ArticleExtractor!
    private var renderer: EditionRenderer!

    /// Editions currently being laid out.
    private(set) var rendering: Set<UUID> = []
    private(set) var renderErrors: [UUID: String] = [:]
    private var renderAgain: Set<UUID> = []
    private(set) var startupError: String?

    private var fetchQueue: [UUID] = []
    private var activeFetches = 0
    private let maxConcurrentFetches = 3

    private static let lastEditionKey = "lastEditionID"

    func start(context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        do { try paths.prepare() } catch { startupError = error.localizedDescription }
        extractor = ArticleExtractor(paths: paths)
        renderer = EditionRenderer(paths: paths)

        // Anything interrupted by quitting starts again.
        for article in fetchAll(Article.self) where article.status.isWorking {
            article.status = .queued
            enqueue(article)
        }
        if fetchAll(Edition.self).isEmpty { _ = createEdition() }
        save()
    }

    // MARK: Editions

    @discardableResult
    func createEdition(name: String = "") -> Edition {
        let number = (fetchAll(Edition.self).map(\.number).max() ?? 0) + 1
        let edition = Edition(number: number, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        context.insert(edition)
        remember(edition)
        save()
        return edition
    }

    /// Where new links go when no particular edition was chosen: the draft you added
    /// to last, else the newest draft, else a new edition.
    func targetEdition(preferring preferred: Edition? = nil) -> Edition {
        if let preferred, preferred.state == .draft { return preferred }
        let drafts = fetchAll(Edition.self).filter { $0.state == .draft }
        if let id = UserDefaults.standard.string(forKey: Self.lastEditionKey).flatMap(UUID.init(uuidString:)),
           let last = drafts.first(where: { $0.id == id }) {
            return last
        }
        return drafts.max { $0.number < $1.number } ?? createEdition()
    }

    func rename(_ edition: Edition, to name: String) {
        edition.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        edition.touch()
        save()
    }

    func markPrinted(_ edition: Edition) {
        edition.state = .printed
        edition.printedAt = .now
        edition.touch()
        save()
    }

    func markDraft(_ edition: Edition) {
        edition.state = .draft
        edition.printedAt = nil
        edition.touch()
        save()
    }

    func delete(_ edition: Edition) {
        for article in edition.articles { delete(article, save: false) }
        try? FileManager.default.removeItem(at: paths.editionFolder(edition.id))
        context.delete(edition)
        save()
    }

    func pdfURL(for edition: Edition) -> URL? {
        let url = paths.editionFolder(edition.id).appendingPathComponent("edition.pdf")
        return FileManager.default.fileExists(atPath: url.path) && edition.renderedAt != nil ? url : nil
    }

    private func remember(_ edition: Edition) {
        UserDefaults.standard.set(edition.id.uuidString, forKey: Self.lastEditionKey)
    }

    // MARK: Cover photo

    /// Looks for another photo online and uses it on the cover, even if a story has one.
    func findCoverPhoto(for edition: Edition) async {
        guard let photo = await fetchCoverPhoto(for: edition) else {
            let alert = NSAlert()
            alert.messageText = "No photo found"
            alert.informativeText = "Galley couldn't find a photo for “\(coverQuery(for: edition))”. Try renaming the edition, or choose a photo of your own."
            alert.runModal()
            return
        }
        apply(photo, to: edition, chosen: true)
    }

    /// Uses a photo from disk on the cover.
    func chooseCoverPhoto(for edition: Edition) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a photo for the cover of \(edition.displayName)"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url)
        else { return }
        guard let photo = CoverPhotoFinder.importPhoto(data, into: paths.editionFolder(edition.id)) else { return }
        apply(photo, to: edition, chosen: true)
    }

    /// Goes back to the cover story's own photo (or an automatic one if it has none).
    func useStoryPhoto(for edition: Edition) {
        removeCoverPhotoFile(of: edition)
        edition.coverPhotoIsChosen = false
        edition.touch()
        save()
    }

    private func coverQuery(for edition: Edition) -> String {
        if !edition.name.isEmpty { return edition.name }
        let cover = edition.printableArticles.first { $0.id == edition.coverArticleID } ?? edition.printableArticles.first
        return CoverPhotoFinder.keywords(from: cover?.title ?? "")
    }

    private func fetchCoverPhoto(for edition: Edition) async -> CoverPhoto? {
        let query = coverQuery(for: edition)
        let photo = await CoverPhotoFinder().find(query: query, excluding: Set(edition.coverPhotoSeen), into: paths.editionFolder(edition.id))
        edition.coverPhotoQuery = query
        return photo
    }

    private func apply(_ photo: CoverPhoto, to edition: Edition, chosen: Bool) {
        removeCoverPhotoFile(of: edition)
        edition.coverPhotoFile = photo.file
        edition.coverPhotoCredit = photo.credit
        edition.coverPhotoIsChosen = chosen
        if let id = photo.sourceID { edition.coverPhotoSeen.append(id) }
        edition.touch()
        save()
    }

    private func removeCoverPhotoFile(of edition: Edition) {
        if let file = edition.coverPhotoFile {
            try? FileManager.default.removeItem(at: paths.editionFolder(edition.id).appendingPathComponent(file))
        }
        edition.coverPhotoFile = nil
        edition.coverPhotoCredit = nil
    }

    // MARK: Articles

    /// Adds links to `edition` (or the usual target). Links already in it are skipped.
    @discardableResult
    func add(_ urls: [URL], to edition: Edition? = nil) -> Edition {
        let edition = edition ?? targetEdition()
        let existing = Set(edition.articles.map(\.sourceURL))
        var position = (edition.articles.map(\.position).max() ?? -1) + 1
        for url in urls where !existing.contains(url) {
            let article = Article(url: url, position: position)
            position += 1
            context.insert(article)
            article.edition = edition
            enqueue(article)
        }
        edition.touch()
        remember(edition)
        save()
        return edition
    }

    func retry(_ article: Article) {
        article.status = .queued
        article.failureReason = nil
        enqueue(article)
        save()
    }

    func delete(_ article: Article, save shouldSave: Bool = true) {
        article.edition?.touch()
        if article.edition?.coverArticleID == article.id { article.edition?.coverArticleID = nil }
        fetchQueue.removeAll { $0 == article.id }
        paths.removeArticle(article.id)
        context.delete(article)
        if shouldSave { save() }
    }

    func move(_ article: Article, to edition: Edition) {
        guard article.edition?.id != edition.id else { return }
        if article.edition?.coverArticleID == article.id { article.edition?.coverArticleID = nil }
        article.edition?.touch()
        article.position = (edition.articles.map(\.position).max() ?? -1) + 1
        article.edition = edition
        edition.touch()
        save()
    }

    func reorder(_ edition: Edition, from source: IndexSet, to destination: Int) {
        var ordered = edition.orderedArticles
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, article) in ordered.enumerated() { article.position = index }
        edition.touch()
        save()
    }

    func makeCover(_ article: Article) {
        guard let edition = article.edition else { return }
        edition.coverArticleID = article.id
        edition.touch()
        save()
    }

    /// Stores an article captured by hand in the browser window.
    func capture(from webView: WKWebView, replacing article: Article?) async {
        let target: Article
        if let article {
            target = article
        } else {
            guard let url = webView.url else { return }
            let edition = targetEdition()
            target = Article(url: url, position: (edition.articles.map(\.position).max() ?? -1) + 1)
            context.insert(target)
            target.edition = edition
        }
        target.status = .fetching
        save()
        let outcome: ExtractionOutcome
        do {
            outcome = try await extractor.extractLoadedPage(webView, requestedURL: target.sourceURL, articleID: target.id)
        } catch {
            outcome = .failed(reason: error.localizedDescription)
        }
        apply(outcome, to: target)
    }

    // MARK: Fetching

    private func enqueue(_ article: Article) {
        if !fetchQueue.contains(article.id) { fetchQueue.append(article.id) }
        pumpQueue()
    }

    private func pumpQueue() {
        while activeFetches < maxConcurrentFetches, !fetchQueue.isEmpty {
            let id = fetchQueue.removeFirst()
            guard let article = fetchArticle(id) else { continue }
            activeFetches += 1
            article.status = .fetching
            save()
            let url = article.sourceURL
            Task {
                let outcome = await extractor.extract(url: url, articleID: id)
                if let article = fetchArticle(id) { apply(outcome, to: article) }
                activeFetches -= 1
                pumpQueue()
            }
        }
    }

    private func apply(_ outcome: ExtractionOutcome, to article: Article) {
        switch outcome {
        case .ready(let metadata):
            article.apply(metadata)
            article.status = .ready
            article.failureReason = nil
        case .needsLogin(let metadata, let reason):
            if let metadata { article.apply(metadata) }
            article.status = .needsLogin
            article.failureReason = reason
        case .needsAttention(let metadata, let reason):
            if let metadata { article.apply(metadata) }
            article.status = .needsAttention
            article.failureReason = reason
        case .failed(let reason):
            article.status = .failed
            article.failureReason = reason
        }
        article.edition?.touch()
        save()
    }

    // MARK: Rendering

    func render(_ edition: Edition) async {
        // One layout at a time per edition. A request that arrives mid-layout runs
        // again afterwards, so the last change always makes it into the PDF.
        guard !rendering.contains(edition.id) else {
            renderAgain.insert(edition.id)
            return
        }
        rendering.insert(edition.id)
        await renderOnce(edition)
        while renderAgain.remove(edition.id) != nil, edition.needsRender(settings: Pref.renderKey) {
            await renderOnce(edition)
        }
        rendering.remove(edition.id)
    }

    private func renderOnce(_ edition: Edition) async {
        renderErrors[edition.id] = nil
        let settingsKey = Pref.renderKey
        let settings = Pref.renderSettings
        let articles = edition.printableArticles
        guard !articles.isEmpty else {
            renderErrors[edition.id] = "Add some articles to see the edition."
            return
        }
        let renderArticles = articles.compactMap { article -> RenderArticle? in
            let folder = paths.articleFolder(article.id)
            guard let metadata = ArticleExtractor.loadMetadata(in: folder) else { return nil }
            return RenderArticle(id: article.id, metadata: metadata, folder: folder)
        }
        var document = EditionDocument(
            masthead: Pref.mastheadName,
            number: edition.number,
            title: edition.name.isEmpty ? nil : edition.name,
            dateLabel: edition.dateLabel,
            articles: renderArticles,
            coverArticleID: edition.coverArticleID,
            settings: settings
        )

        // Cover photo: the reader's choice wins. Otherwise, if no story has a picture,
        // find one online (again if the edition was renamed since).
        if !edition.coverPhotoIsChosen && settings.imageMode != .none && document.needsCoverPhoto {
            if edition.coverPhotoFile == nil || edition.coverPhotoQuery != coverQuery(for: edition),
               let photo = await fetchCoverPhoto(for: edition) {
                apply(photo, to: edition, chosen: false)
            }
        }
        if let file = edition.coverPhotoFile, edition.coverPhotoIsChosen || document.needsCoverPhoto {
            document.coverPhoto = paths.editionFolder(edition.id).appendingPathComponent(file)
            document.coverPhotoCredit = edition.coverPhotoCredit
        }

        // Read after the cover photo step, which counts as a change to the edition.
        let version = edition.contentVersion
        do {
            let result = try await renderer.render(document, into: paths.editionFolder(edition.id))
            edition.pageCount = result.pageCount
            edition.renderedAt = .now
            edition.renderedVersion = version
            edition.renderedSettings = settingsKey
            for article in edition.articles { article.startPage = result.articleStartPages[article.id] }
            save()
        } catch {
            renderErrors[edition.id] = error.localizedDescription
        }
    }

    // MARK: Helpers

    func save() {
        try? context.save()
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    private func fetchArticle(_ id: UUID) -> Article? {
        try? context.fetch(FetchDescriptor<Article>(predicate: #Predicate { $0.id == id })).first
    }
}
