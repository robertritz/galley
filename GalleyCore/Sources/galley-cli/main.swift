import AppKit
import GalleyCore

// A small command-line front end to GalleyCore, used for development and testing.
//
//     galley-cli <url> [<url> …] [--paper a4|letter] [--images color|grayscale|none] [--out edition.pdf]
//
// Files go to $GALLEY_ROOT (default: ~/Library/Application Support/Galley).

@MainActor
func run() async -> Int32 {
    var urls: [URL] = []
    var paper = PaperSize.regionDefault
    var imageMode = ImageMode.color
    var out: URL?
    var args = CommandLine.arguments.dropFirst()
    while let arg = args.popFirst() {
        switch arg {
        case "--paper": paper = args.popFirst().flatMap(PaperSize.init(rawValue:)) ?? paper
        case "--images": imageMode = args.popFirst().flatMap(ImageMode.init(rawValue:)) ?? imageMode
        case "--out": out = args.popFirst().map { URL(fileURLWithPath: $0) }
        default:
            if let url = URL(string: arg), url.scheme?.hasPrefix("http") == true { urls.append(url) }
            else { print("Ignoring \(arg)") }
        }
    }
    guard !urls.isEmpty else {
        print("usage: galley-cli <url> [<url> …] [--paper a4|letter] [--images color|grayscale|none] [--out edition.pdf]")
        return 64
    }

    let paths = GalleyPaths.default
    do { try paths.prepare() } catch { print("error: \(error.localizedDescription)"); return 1 }
    print("Library: \(paths.root.path)")

    let extractor = ArticleExtractor(paths: paths)
    var articles: [RenderArticle] = []
    for url in urls {
        let id = UUID()
        let started = Date()
        let outcome = await extractor.extract(url: url, articleID: id)
        let seconds = String(format: "%.1fs", Date().timeIntervalSince(started))
        switch outcome {
        case .ready(let m):
            print("✓ \(m.title) — \(m.siteName ?? "?"), \(m.wordCount) words, images: \(m.bodyHasImages ? "yes" : "no") [\(seconds)]")
            articles.append(RenderArticle(id: id, metadata: m, folder: paths.articleFolder(id)))
        case .needsLogin(let m, let reason), .needsAttention(let m, let reason):
            print("! \(url.absoluteString): \(reason) [\(seconds)]")
            if let m { articles.append(RenderArticle(id: id, metadata: m, folder: paths.articleFolder(id))) }
        case .failed(let reason):
            print("✗ \(url.absoluteString): \(reason) [\(seconds)]")
        }
    }
    guard !articles.isEmpty else { return 1 }

    let editionID = UUID()
    let document = EditionDocument(
        masthead: "Galley",
        number: 1,
        dateLabel: Date().formatted(.dateTime.month(.wide).year()),
        articles: articles,
        settings: RenderSettings(paper: paper, imageMode: imageMode)
    )
    do {
        let started = Date()
        let result = try await EditionRenderer(paths: paths).render(document, into: paths.editionFolder(editionID))
        print("Rendered \(result.pageCount) pages in \(String(format: "%.1fs", Date().timeIntervalSince(started))): \(result.pdfURL.path)")
        print("Article start pages: \(articles.map { result.articleStartPages[$0.id].map(String.init) ?? "?" }.joined(separator: ", "))")
        if let out {
            try? FileManager.default.removeItem(at: out)
            try FileManager.default.copyItem(at: result.pdfURL, to: out)
            print("Copied to \(out.path)")
        }
        return 0
    } catch {
        print("error: \(error.localizedDescription)")
        return 1
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in
    exit(await run())
}
app.run()
