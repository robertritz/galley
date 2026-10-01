import GalleyCore
import SwiftData
import SwiftUI

/// The middle column for an edition: its articles in print order.
struct EditionView: View {
    @Bindable var edition: Edition
    @Binding var selectedArticleID: UUID?
    @Binding var showingAddLink: Bool
    @Binding var naming: EditionNaming
    @Environment(Library.self) private var library
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Edition.number, order: .reverse) private var editions: [Edition]

    var body: some View {
        List(selection: $selectedArticleID) {
            Section {
                ForEach(edition.orderedArticles) { article in
                    ArticleRow(article: article, isCover: isCover(article))
                        .tag(article.id)
                        .contextMenu { menu(for: article) }
                }
                .onMove { library.reorder(edition, from: $0, to: $1) }
            } header: {
                header
            }
        }
        .overlay {
            if edition.articles.isEmpty {
                ContentUnavailableView {
                    Label("No Articles Yet", systemImage: "link.badge.plus")
                } description: {
                    Text("Paste a link (⌘V), drop one here, or press ⌘L.\nArticles you add while looking at this edition go into it.")
                } actions: {
                    Button("Add Link…") { showingAddLink = true }
                }
            }
        }
        .navigationTitle(edition.displayName)
        .navigationSubtitle(edition.name.isEmpty ? (edition.state == .printed ? "Printed" : "Draft") : "No. \(edition.number)")
        .toolbar {
            ToolbarItemGroup {
                Button { showingAddLink = true } label: { Label("Add Link", systemImage: "plus") }
                    .help("Add links to this edition (⌘L)")
                Menu {
                    Button("Rename…") { naming = .rename(edition) }
                    Divider()
                    Section("Cover Photo") {
                        Button("Find a Photo Online") { Task { await library.findCoverPhoto(for: edition) } }
                        Button("Choose a Photo…") { library.chooseCoverPhoto(for: edition) }
                        Button("Use the Cover Story’s Photo") { library.useStoryPhoto(for: edition) }
                            .disabled(!edition.coverPhotoIsChosen)
                    }
                    Divider()
                    if edition.state == .draft {
                        Button("Mark as Printed") { library.markPrinted(edition) }
                    } else {
                        Button("Move Back to Editions") { library.markDraft(edition) }
                    }
                } label: {
                    Label("Edition", systemImage: "ellipsis.circle")
                }
                .help("Rename, change the cover photo, or mark as printed")
            }
        }
    }

    private var header: some View {
        let printable = edition.printableArticles
        let minutes = printable.reduce(0) { $0 + $1.readingMinutes }
        var line = "\(printable.count) \(printable.count == 1 ? "story" : "stories") · about \(minutes) min of reading"
        if let pages = edition.pageCount, !printable.isEmpty { line += " · \(pages) pages" }
        return VStack(alignment: .leading, spacing: 2) {
            Text(line)
            if let printed = edition.printedAt {
                Text("Printed \(printed.formatted(date: .long, time: .omitted))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .textCase(nil)
        .padding(.vertical, 4)
    }

    private func isCover(_ article: Article) -> Bool {
        if let id = edition.coverArticleID { return id == article.id }
        return edition.printableArticles.first(where: { $0.leadImageFile != nil })?.id == article.id
    }

    @ViewBuilder private func menu(for article: Article) -> some View {
        Button("Use as Cover Story") { library.makeCover(article) }
            .disabled(!article.isPrintable)
        Button("Open Original") { NSWorkspace.shared.open(article.sourceURL) }
        Button("Fix in Galley Browser…") {
            openWindow(id: "browser", value: BrowserRequest(url: article.sourceURL, articleID: article.id))
        }
        Button("Fetch Again") { library.retry(article) }
        Divider()
        Menu("Move To") {
            ForEach(editions.filter { $0.id != edition.id }) { other in
                Button(other.displayName + (other.state == .printed ? " (printed)" : "")) { library.move(article, to: other) }
            }
            Divider()
            Button("New Edition") {
                let other = library.createEdition()
                library.move(article, to: other)
            }
        }
        Button("Remove", role: .destructive) {
            if selectedArticleID == article.id { selectedArticleID = nil }
            library.delete(article)
        }
    }
}

struct ArticleRow: View {
    let article: Article
    var isCover = false
    var showEdition = false
    @Environment(Library.self) private var library

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(article.displaySite.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red.opacity(0.85))
                        .lineLimit(1)
                    if isCover {
                        Text("COVER")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 4)
                            .background(.quaternary, in: .rect(cornerRadius: 3))
                    }
                }
                Text(article.title)
                    .font(.headline)
                    .lineLimit(3)
                statusLine
            }
            Spacer(minLength: 0)
            if let page = article.startPage, article.isPrintable, !showEdition {
                Text("\(page)")
                    .font(.title3.weight(.light).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var statusLine: some View {
        switch article.status {
        case .queued, .fetching:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(article.status.label)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .ready:
            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .needsLogin, .needsAttention, .failed:
            Label(article.failureReason ?? article.status.label, systemImage: article.status == .failed ? "xmark.octagon" : "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(article.status == .failed ? .red : .orange)
                .lineLimit(2)
        }
    }

    private var details: String {
        var parts: [String] = []
        if let by = article.byline { parts.append(by) }
        parts.append("\(article.readingMinutes) min")
        if showEdition, let edition = article.edition { parts.append(edition.displayName) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var thumbnail: some View {
        let url = article.leadImageFile.map { library.paths.articleFolder(article.id).appendingPathComponent($0) }
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "doc.text").font(.title2).foregroundStyle(.tertiary)
            }
        }
        .frame(width: 54, height: 54)
        .background(.quinary)
        .clipShape(.rect(cornerRadius: 5))
    }
}

/// Library lists: every article, or only the ones with problems.
struct ArticleListView: View {
    let title: String
    let articles: [Article]
    @Binding var selectedArticleID: UUID?
    @Environment(Library.self) private var library
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        List(articles, selection: $selectedArticleID) { article in
            ArticleRow(article: article, showEdition: true)
                .tag(article.id)
                .contextMenu {
                    Button("Open Original") { NSWorkspace.shared.open(article.sourceURL) }
                    Button("Fix in Galley Browser…") {
                        openWindow(id: "browser", value: BrowserRequest(url: article.sourceURL, articleID: article.id))
                    }
                    Button("Fetch Again") { library.retry(article) }
                    Divider()
                    Button("Remove", role: .destructive) {
                        if selectedArticleID == article.id { selectedArticleID = nil }
                        library.delete(article)
                    }
                }
        }
        .overlay {
            if articles.isEmpty {
                ContentUnavailableView(title == "Needs Attention" ? "Nothing Needs Attention" : "No Articles",
                                       systemImage: title == "Needs Attention" ? "checkmark.circle" : "doc.text")
            }
        }
        .navigationTitle(title)
    }
}

struct ArticleDetailView: View {
    let article: Article
    @Environment(Library.self) private var library
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(article.displaySite.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red.opacity(0.85))
                Text(article.title).font(.largeTitle.weight(.bold))
                if let excerpt = article.excerpt {
                    Text(excerpt).font(.title3).italic().foregroundStyle(.secondary)
                }
                Text([article.byline, article.publishedAt?.formatted(date: .long, time: .omitted), article.wordCount > 0 ? "\(article.wordCount) words" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Link(article.sourceURL.absoluteString, destination: article.sourceURL)
                    .font(.callout)

                if article.status.isProblem {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(article.failureReason ?? article.status.label, systemImage: "exclamationmark.triangle")
                            Text("If the site needs a login or shows a pop-up, open it in Galley's browser, deal with it there, then press Add to Galley.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("Fix in Galley Browser…") {
                                    openWindow(id: "browser", value: BrowserRequest(url: article.sourceURL, articleID: article.id))
                                }
                                Button("Fetch Again") { library.retry(article) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }
}
