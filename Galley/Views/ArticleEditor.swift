import GalleyCore
import SwiftUI
import WebKit

/// Shows an article as Galley extracted it, and lets you leave parts out of the
/// printout: click a paragraph, heading, list or picture to strike it, click again
/// to keep it. Saving rewrites the article's saved copy.
struct ArticleEditor: View {
    let article: Article
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var page = EditorPage()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(article.title).font(.headline).lineLimit(1)
                    Text(page.removedCount == 0
                         ? "Click a paragraph or picture to leave it out of the printout."
                         : "\(page.removedCount) \(page.removedCount == 1 ? "part" : "parts") left out. Click again to keep.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task {
                        if let result = await page.result() { library.saveEdits(to: article, result) }
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(page.removedCount == 0)
            }
            .padding(14)
            Divider()
            EditorWebView(page: page)
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 600, idealHeight: 820)
        .task { page.load(article: article, folder: library.paths.articleFolder(article.id)) }
    }
}

/// What the editor hands back: the remaining HTML and what it now contains.
struct ArticleEdits {
    var html: String
    var wordCount: Int
    /// `images/…` paths still in the article, in order.
    var images: [String]
}

@Observable
final class EditorPage: NSObject, WKScriptMessageHandler {
    let webView: WKWebView
    var removedCount = 0

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(self, name: "galley")
    }

    func load(article: Article, folder: URL) {
        let body = (try? String(contentsOf: folder.appendingPathComponent("article.html"), encoding: .utf8)) ?? ""
        let shell = folder.appendingPathComponent(".editor.html")
        try? Self.shell(title: article.title, site: article.displaySite, body: body)
            .write(to: shell, atomically: true, encoding: .utf8)
        webView.loadFileURL(shell, allowingReadAccessTo: folder)
    }

    func result() async -> ArticleEdits? {
        guard let dict = try? await webView.evaluateJavaScript("galleyResult()") as? [String: Any],
              let html = dict["html"] as? String
        else { return nil }
        return ArticleEdits(html: html, wordCount: dict["words"] as? Int ?? 0, images: dict["images"] as? [String] ?? [])
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let count = message.body as? Int { removedCount = count }
    }

    private static func shell(title: String, site: String, body: String) -> String {
        let esc = { (s: String) in s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;") }
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <style>
          :root { color-scheme: light dark; }
          body { font: 17px/1.55 ui-serif, Georgia, serif; max-width: 660px; margin: 36px auto 80px; padding: 0 28px; }
          .site { font: 600 11px/1 -apple-system, sans-serif; letter-spacing: .1em; text-transform: uppercase; color: #b3261e; }
          h1.title { font-size: 30px; line-height: 1.15; margin: 8px 0 28px; }
          img { max-width: 100%; height: auto; display: block; margin: 0 auto; }
          figcaption { font: 12px/1.4 -apple-system, sans-serif; color: gray; margin-top: 6px; }
          .unit { cursor: pointer; border-radius: 6px; transition: background .1s, opacity .1s; }
          .unit.hover { background: rgba(127,127,127,.12); outline: 2px solid rgba(127,127,127,.25); outline-offset: 4px; }
          .unit.removed { opacity: .28; text-decoration: line-through; outline: 2px dashed #b3261e; outline-offset: 4px; }
          a { color: inherit; }
        </style></head><body>
        <div class="site">\(esc(site))</div>
        <h1 class="title">\(esc(title))</h1>
        <main id="galley-body">\(body)</main>
        <script>
          const units = "p, figure, img, blockquote, ul, ol, table, h2, h3, h4, h5, pre, aside, hr, dl";
          const body = document.getElementById("galley-body");
          const unitOf = (el) => {
            if (!el || !body.contains(el)) return null;
            return el.closest("figure") || el.closest(units);
          };
          for (const el of body.querySelectorAll(units)) el.classList.add("unit");
          let hovered = null;
          body.addEventListener("mouseover", (e) => {
            const u = unitOf(e.target);
            if (hovered && hovered !== u) hovered.classList.remove("hover");
            hovered = u;
            if (u) u.classList.add("hover");
          });
          body.addEventListener("mouseleave", () => hovered && hovered.classList.remove("hover"));
          body.addEventListener("click", (e) => {
            e.preventDefault();
            const u = unitOf(e.target);
            if (!u) return;
            u.classList.toggle("removed");
            window.webkit.messageHandlers.galley.postMessage(body.querySelectorAll(".removed").length);
          });
          window.galleyResult = () => {
            const copy = body.cloneNode(true);
            for (const el of copy.querySelectorAll(".removed")) el.remove();
            for (const el of copy.querySelectorAll(".unit")) {
              el.classList.remove("unit", "hover");
              if (!el.className) el.removeAttribute("class");
            }
            const text = copy.textContent || "";
            return {
              html: copy.innerHTML,
              words: (text.match(/\\S+/g) || []).length,
              images: [...copy.querySelectorAll("img")].map((i) => i.getAttribute("src")).filter((s) => s && s.startsWith("images/")),
            };
          };
        </script>
        </body></html>
        """
    }
}

private struct EditorWebView: NSViewRepresentable {
    let page: EditorPage
    func makeNSView(context: Context) -> WKWebView { page.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
