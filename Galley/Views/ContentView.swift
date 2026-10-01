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
    /// The edition whose name is being edited in the sidebar.
    @State private var renamingID: UUID?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, renamingID: $renamingID)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } content: {
            content
                .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 560)
        } detail: {
            detail
        }
        .sheet(isPresented: $showingAddLink) {
            AddLinkSheet(target: selectedEdition) { edition in selection = .edition(edition.id) }
        }
        .onPasteCommand(of: [.url, .plainText]) { providers in
            Task { await addLinks(from: providers) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            addWeb(urls)
        }
        .focusedSceneValue(\.galleyActions, actions)
        .onAppear(perform: selectAnEdition)
        .onChange(of: editions.count, selectAnEdition)
        .onChange(of: selection) { selectedArticleID = nil }
        .alert("Galley couldn't start", isPresented: .constant(library.startupError != nil)) {
            Button("Quit") { NSApp.terminate(nil) }
        } message: {
            Text(library.startupError ?? "")
        }
    }

    /// Start on the newest draft edition.
    private func selectAnEdition() {
        if let current = selection, case .edition(let id) = current, editions.contains(where: { $0.id == id }) { return }
        if case .allArticles = selection { return }
        if case .needsAttention = selection { return }
        if let edition = editions.first(where: { $0.state == .draft }) ?? editions.first {
            selection = .edition(edition.id)
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
                EditionView(edition: edition, selectedArticleID: $selectedArticleID, showingAddLink: $showingAddLink, renamingID: $renamingID)
            } else {
                ContentUnavailableView("No Edition", systemImage: "newspaper")
            }
        case .allArticles:
            ArticleListView(title: "All Articles", articles: articles, selectedArticleID: $selectedArticleID)
        case .needsAttention:
            ArticleListView(title: "Needs Attention", articles: articles.filter { $0.status.isProblem }, selectedArticleID: $selectedArticleID)
        case nil:
            ContentUnavailableView {
                Label("No Edition Selected", systemImage: "newspaper")
            } actions: {
                Button("New Edition") { newEdition() }
            }
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
            newEdition: newEdition,
            addLink: { showingAddLink = true },
            openBrowser: { openWindow(id: "browser", value: BrowserRequest()) },
            printEdition: { if let edition { Task { await EditionOutput.print(edition, library: library) } } },
            exportPDF: { if let edition { Task { await EditionOutput.export(edition, library: library) } } },
            canPrint: edition.map { !$0.printableArticles.isEmpty } ?? false
        )
    }

    /// Makes an edition and puts its name straight into editing, like a new Finder folder.
    private func newEdition() {
        let edition = library.createEdition()
        selection = .edition(edition.id)
        renamingID = edition.id
    }

    /// Links go into the edition on screen, or the usual target if none is.
    @discardableResult
    private func addWeb(_ urls: [URL]) -> Bool {
        let web = urls.filter { $0.scheme == "http" || $0.scheme == "https" }
        guard !web.isEmpty else { return false }
        let edition = library.add(web, to: selectedEdition.flatMap { $0.state == .draft ? $0 : nil })
        selection = .edition(edition.id)
        return true
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
        addWeb(urls)
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
