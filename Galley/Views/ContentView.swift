import GalleyCore
import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: Hashable {
    case edition(UUID)
    case allArticles
    case needsAttention
}

struct ContentView: View {
    @Environment(Library.self) private var library
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Edition.number, order: .reverse) private var editions: [Edition]
    @Query(sort: \Article.addedAt, order: .reverse) private var articles: [Article]

    @State private var selection: SidebarItem?
    @State private var selectedArticleID: UUID?
    @State private var showingAddLink = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } content: {
            content
                .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 560)
        } detail: {
            detail
        }
        .sheet(isPresented: $showingAddLink) {
            AddLinkSheet()
        }
        .onPasteCommand(of: [.url, .plainText]) { providers in
            Task { await addLinks(from: providers) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let web = urls.filter { $0.scheme == "http" || $0.scheme == "https" }
            guard !web.isEmpty else { return false }
            library.add(web)
            selection = .edition(library.openEdition().id)
            return true
        }
        .focusedSceneValue(\.galleyActions, actions)
        .onAppear(perform: selectOpenEdition)
        .onChange(of: editions.count, selectOpenEdition)
        .onChange(of: selection) { selectedArticleID = nil }
        .alert("Galley couldn't start", isPresented: .constant(library.startupError != nil)) {
            Button("Quit") { NSApp.terminate(nil) }
        } message: {
            Text(library.startupError ?? "")
        }
    }

    /// Start on the edition that's collecting articles.
    private func selectOpenEdition() {
        if selection == nil, let open = editions.first(where: { $0.state == .open }) {
            selection = .edition(open.id)
        }
    }

    private var selectedEdition: Edition? {
        guard case .edition(let id) = selection else { return nil }
        return editions.first { $0.id == id }
    }

    @ViewBuilder private var content: some View {
        switch selection {
        case .edition:
            if let edition = selectedEdition {
                EditionView(edition: edition, selectedArticleID: $selectedArticleID, showingAddLink: $showingAddLink)
            } else {
                ContentUnavailableView("No Edition", systemImage: "newspaper")
            }
        case .allArticles:
            ArticleListView(title: "All Articles", articles: articles, selectedArticleID: $selectedArticleID)
        case .needsAttention:
            ArticleListView(title: "Needs Attention", articles: articles.filter { $0.status.isProblem }, selectedArticleID: $selectedArticleID)
        case nil:
            ContentUnavailableView("Select an Edition", systemImage: "newspaper")
        }
    }

    @ViewBuilder private var detail: some View {
        if let edition = selectedEdition {
            EditionPreview(edition: edition, selectedArticleID: selectedArticleID)
        } else if let id = selectedArticleID, let article = articles.first(where: { $0.id == id }) {
            ArticleDetailView(article: article)
        } else {
            ContentUnavailableView("Nothing Selected", systemImage: "doc.richtext")
        }
    }

    // MARK: Actions

    private var actions: GalleyActions {
        let edition = selectedEdition
        return GalleyActions(
            addLink: { showingAddLink = true },
            openBrowser: { openWindow(id: "browser", value: BrowserRequest()) },
            printEdition: { if let edition { Task { await EditionOutput.print(edition, library: library) } } },
            exportPDF: { if let edition { Task { await EditionOutput.export(edition, library: library) } } },
            canPrint: edition.map { !$0.printableArticles.isEmpty } ?? false
        )
    }

    private func addLinks(from providers: [NSItemProvider]) async {
        var urls: [URL] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                urls.append(url)
            } else if let data = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? Data,
                      let text = String(data: data, encoding: .utf8) {
                urls.append(contentsOf: LinkParser.urls(in: text))
            } else if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                urls.append(contentsOf: LinkParser.urls(in: text))
            }
        }
        let web = urls.filter { $0.scheme == "http" || $0.scheme == "https" }
        guard !web.isEmpty else { return }
        library.add(web)
        selection = .edition(library.openEdition().id)
    }
}

enum LinkParser {
    /// Every http(s) link in a block of text, in order, without duplicates.
    static func urls(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var seen = Set<URL>()
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let url = match.url, url.scheme == "http" || url.scheme == "https", seen.insert(url).inserted else { return nil }
            return url
        }
    }
}
