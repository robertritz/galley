import Foundation

/// Builds the single HTML document for an edition: cover, contents, then one
/// `<article>` per story. The theme's CSS is inlined because Paged.js reads
/// stylesheets itself and can't fetch `file://` URLs.
struct EditionHTML {
    let edition: EditionDocument
    let paths: GalleyPaths

    func build() throws -> String {
        let theme = paths.themeFolder(edition.settings.themeID)
        let themeBase = theme.absoluteString
        let fonts = try String(contentsOf: theme.appendingPathComponent("fonts.css"), encoding: .utf8)
            .replacingOccurrences(of: "url(fonts/", with: "url(\(themeBase)fonts/")
        let css = try String(contentsOf: theme.appendingPathComponent("theme.css"), encoding: .utf8)
        let js = paths.jsFolder.absoluteString

        let articles = edition.articles
        // The cover story is the one chosen in the app, or else the first with a picture.
        let cover = articles.first { $0.id == edition.coverArticleID }
            ?? articles.first { $0.metadata.leadImageFile != nil }
            ?? articles.first

        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <title>\(esc(edition.masthead)) No. \(edition.number)</title>
        <style>\(fonts)</style>
        <style>\(css)</style>
        <style>\(settingsCSS)</style>
        <script>
        window.PagedConfig = { auto: false };
        // The render window is invisible, so WebKit never delivers animation frames.
        // Paged.js schedules its work with them; run those callbacks on timers instead.
        window.requestAnimationFrame = (cb) => setTimeout(() => cb(performance.now()), 0);
        window.requestIdleCallback = (cb) => setTimeout(() => cb({ didTimeout: false, timeRemaining: () => 50 }), 0);
        </script>
        <script src="\(js)paged.polyfill.js"></script>
        <script src="\(js)galley-render.js"></script>
        </head>
        <body class="images-\(edition.settings.imageMode.rawValue)">
        \(coverHTML(cover: cover))
        \(contentsHTML)
        \(articles.map(articleHTML).joined(separator: "\n"))
        </body>
        </html>
        """
    }

    private var runningHead: String {
        "\(edition.masthead) · No. \(edition.number) · \(edition.dateLabel)"
    }

    private var settingsCSS: String {
        let paper = edition.settings.paper
        return """
        @page { size: \(paper.cssSize); @top-left { content: "\(cssString(runningHead))"; } }
        :root { --paper-height: \(paper == .a4 ? "297mm" : "279.4mm"); }
        """
    }

    // MARK: Cover

    private func coverHTML(cover: RenderArticle?) -> String {
        let others = edition.articles.filter { $0.id != cover?.id }.prefix(4)
        let image: String
        if let cover, let lead = cover.metadata.leadImageFile, edition.settings.imageMode != .none {
            image = #"<div class="cover-image"><img src="\#(fileURL(cover, lead))" alt=""></div>"#
        } else {
            image = #"<div class="cover-image cover-image-empty"></div>"#
        }
        let lead = cover.map { a in
            """
            <a class="cover-lead" href="#a-\(a.id.uuidString)">
              <span class="cover-kicker">\(esc(a.metadata.siteName ?? ""))</span>
              <span class="cover-title">\(esc(a.metadata.title))</span>
            </a>
            """
        } ?? ""
        let lines = others.map { a in
            """
            <li><a href="#a-\(a.id.uuidString)"><span class="cover-line-title">\(esc(a.metadata.title))</span><span class="cover-line-site">\(esc(a.metadata.siteName ?? ""))</span></a></li>
            """
        }.joined()
        let count = edition.articles.count
        return """
        <section class="cover">
          <header class="cover-masthead">
            <h1 class="masthead">\(esc(edition.masthead))</h1>
            <p class="issue-line"><span>No. \(edition.number)</span><span>\(esc(edition.dateLabel))</span><span>\(count) \(count == 1 ? "story" : "stories")</span></p>
          </header>
          \(image)
          <div class="cover-text">
            \(lead)
            <ul class="cover-lines">\(lines)</ul>
          </div>
        </section>
        """
    }

    // MARK: Contents

    private var contentsHTML: String {
        let entries = edition.articles.map { a in
            let m = a.metadata
            let byline = [m.byline, "\(m.readingMinutes) min"].compactMap { $0 }.joined(separator: " · ")
            return """
            <li>
              <a class="toc-page" href="#a-\(a.id.uuidString)"></a>
              <div class="toc-entry">
                <p class="toc-kicker">\(esc(m.siteName ?? ""))</p>
                <p class="toc-title">\(esc(m.title))</p>
                \(m.excerpt.map { "<p class=\"toc-dek\">\(esc(truncate($0, 200)))</p>" } ?? "")
                <p class="toc-byline">\(esc(byline))</p>
              </div>
            </li>
            """
        }.joined()
        return """
        <section class="contents">
          <h2 class="contents-heading">Contents</h2>
          <ol class="toc">\(entries)</ol>
          <p class="colophon">\(esc(edition.masthead)) No. \(edition.number) was printed with Galley on \(Self.dayFormatter.string(from: Date())).</p>
        </section>
        """
    }

    // MARK: Articles

    private func articleHTML(_ article: RenderArticle) -> String {
        let m = article.metadata
        var body = (try? String(contentsOf: article.folder.appendingPathComponent("article.html"), encoding: .utf8)) ?? ""
        // Image paths in article.html are relative to the article folder.
        body = body.replacingOccurrences(of: "src=\"images/", with: "src=\"\(article.folder.absoluteString)images/")

        var bylineParts: [String] = []
        if let by = m.byline { bylineParts.append("By \(esc(by))") }
        if let date = m.publishedAt { bylineParts.append(Self.dayFormatter.string(from: date)) }
        bylineParts.append("\(m.readingMinutes) min read")

        var lead = ""
        if !m.bodyHasImages, let file = m.leadImageFile {
            lead = #"<figure class="lead"><img src="\#(fileURL(article, file))" alt=""></figure>"#
        }
        let source = m.canonicalURL ?? m.sourceURL
        let lang = m.language.map { " lang=\"\(esc($0))\"" } ?? ""

        return """
        <article class="story" id="a-\(article.id.uuidString)" data-id="\(article.id.uuidString)"\(lang)>
          <header class="opener">
            <p class="kicker">\(esc(m.siteName ?? source.host() ?? ""))</p>
            <h1 class="headline">\(esc(m.title))</h1>
            \(m.excerpt.map { "<p class=\"dek\">\(esc(truncate($0, 320)))</p>" } ?? "")
            <p class="byline">\(bylineParts.joined(separator: " · "))</p>
            \(lead)
          </header>
          <div class="body">
          \(body)
          </div>
          <footer class="source">
            <div class="notes-block"><p class="notes-heading">Links</p><ol class="notes"></ol></div>
            <div class="source-line">
              <img class="qr" src="\(article.folder.absoluteString)qr.png" alt="">
              <p>Read the original at<br><span class="source-url">\(esc(displayURL(source)))</span></p>
            </div>
          </footer>
        </article>
        """
    }

    // MARK: Helpers

    private func fileURL(_ article: RenderArticle, _ relative: String) -> String {
        article.folder.appendingPathComponent(relative).absoluteString
    }

    private func displayURL(_ url: URL) -> String {
        var s = url.absoluteString
        for prefix in ["https://", "http://", "www."] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
        return truncate(s, 90)
    }

    private func truncate(_ s: String, _ limit: Int) -> String {
        s.count <= limit ? s : String(s.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func cssString(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()
}
