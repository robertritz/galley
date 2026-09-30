import AppKit
import Foundation
import GalleyCore
import Observation
import SwiftData
import UserNotifications
import WebKit

/// Owns the app's behaviour: adding links, fetching articles, keeping exactly one
/// open edition, closing editions on schedule, and rendering PDFs.
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
    private let maxConcurrentFetches = 2
    private var scheduleTimer: Timer?

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
        _ = openEdition()
        checkSchedule()
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
            Task { @MainActor in self.checkSchedule() }
        }
        save()
    }

    // MARK: Editions

    /// The edition that new articles go into. Created on demand.
    func openEdition() -> Edition {
        let open = fetchAll(Edition.self).filter { $0.state == .open }.sorted { $0.number < $1.number }
        if let edition = open.last { return edition }
        let number = (fetchAll(Edition.self).map(\.number).max() ?? 0) + 1
        let start = Date.now
        let cadence = Pref.cadence
        let end = cadence.nextClose(after: start)
        let edition = Edition(number: number, periodStart: start, periodEnd: end, dateLabel: cadence.dateLabel(start: start, end: end ?? start))
        context.insert(edition)
        save()
        return edition
    }

    /// Closes the open edition if its period is over.
    func checkSchedule() {
        guard context != nil else { return }
        let edition = openEdition()
        guard let end = edition.periodEnd, end <= .now else { return }
        if edition.articles.isEmpty {
            // Nothing to print: roll the empty edition over to the next period instead.
            let cadence = Pref.cadence
            edition.periodStart = .now
            edition.periodEnd = cadence.nextClose(after: .now)
            edition.dateLabel = cadence.dateLabel(start: edition.periodStart, end: edition.periodEnd ?? .now)
            save()
            return
        }
        close(edition, notify: true)
    }

    /// Called when the cadence setting changes: the open edition now closes at the new time.
    func cadenceChanged() {
        let edition = openEdition()
        let cadence = Pref.cadence
        edition.periodEnd = cadence.nextClose(after: .now)
        edition.dateLabel = cadence.dateLabel(start: edition.periodStart, end: edition.periodEnd ?? .now)
        edition.touch()
        save()
    }

    func close(_ edition: Edition, notify: Bool = false) {
        guard edition.state == .open else { return }
        edition.state = .closed
        edition.closedAt = .now
        let cadence = Pref.cadence
        let end = min(edition.periodEnd ?? .now, .now)
        edition.dateLabel = cadence.dateLabel(start: edition.periodStart, end: max(end, edition.periodStart))
        // Articles still fetching or broken move on to the next edition.
        let next = openEdition()
        for article in edition.articles where !article.isPrintable {
            move(article, to: next)
        }
        edition.touch()
        save()
        Task {
            await render(edition)
            if notify { await notifyReady(edition) }
        }
    }

    func markPrinted(_ edition: Edition) {
        edition.state = .printed
        edition.printedAt = .now
        save()
    }

    func delete(_ edition: Edition) {
        for article in edition.articles { delete(article, save: false) }
        try? FileManager.default.removeItem(at: paths.editionFolder(edition.id))
        context.delete(edition)
        save()
        _ = openEdition()
    }

    func pdfURL(for edition: Edition) -> URL? {
        let url = paths.editionFolder(edition.id).appendingPathComponent("edition.pdf")
        return FileManager.default.fileExists(atPath: url.path) && edition.renderedAt != nil ? url : nil
    }

    // MARK: Articles

    /// Adds links to the open edition. Duplicates of articles already in it are skipped.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        let edition = openEdition()
        let existing = Set(edition.articles.map(\.sourceURL))
        var position = (edition.articles.map(\.position).max() ?? -1) + 1
        var added = 0
        for url in urls where !existing.contains(url) {
            let article = Article(url: url, position: position)
            position += 1
            context.insert(article)
            article.edition = edition
            enqueue(article)
            added += 1
        }
        edition.touch()
        save()
        return added
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
            let edition = openEdition()
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

        let version = edition.contentVersion
        let settingsKey = Pref.renderKey
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
        let document = EditionDocument(
            masthead: Pref.mastheadName,
            number: edition.number,
            dateLabel: edition.state == .open ? Pref.cadence.dateLabel(start: edition.periodStart, end: edition.periodEnd ?? .now) : edition.dateLabel,
            articles: renderArticles,
            coverArticleID: edition.coverArticleID,
            settings: Pref.renderSettings
        )
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

    // MARK: Notifications

    private func notifyReady(_ edition: Edition) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(Pref.mastheadName) \(edition.title) is ready to print"
        let stories = edition.printableArticles.count
        content.body = "\(stories) \(stories == 1 ? "story" : "stories")" + (edition.pageCount.map { ", \($0) pages" } ?? "")
        try? await center.add(UNNotificationRequest(identifier: edition.id.uuidString, content: content, trigger: nil))
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
