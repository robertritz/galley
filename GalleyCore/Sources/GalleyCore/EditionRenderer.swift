import AppKit
import WebKit

/// Lays out an edition with Paged.js inside an offscreen WebKit view and writes a PDF.
///
/// Pipeline: build `edition.html` → load it → `galleyRender()` paginates with Paged.js
/// → capture each `.pagedjs_page` with `createPDF` → join into one PDF at the real
/// paper size.
@MainActor
public final class EditionRenderer {
    private let paths: GalleyPaths

    public init(paths: GalleyPaths) {
        self.paths = paths
    }

    public func render(_ edition: EditionDocument, into folder: URL) async throws -> RenderResult {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let htmlURL = folder.appendingPathComponent("edition.html")
        try EditionHTML(edition: edition, paths: paths).build().write(to: htmlURL, atomically: true, encoding: .utf8)

        let clock = ContinuousClock()
        var mark = clock.now
        func lap(_ label: String) {
            if ProcessInfo.processInfo.environment["GALLEY_DEBUG"] != nil {
                print("render: \(label) \(clock.now - mark)")
            }
            mark = clock.now
        }
        let web = OffscreenWebView(size: CGSize(width: 900, height: 1200), dataStore: .nonPersistent())
        defer { web.close() }
        try await web.loadFile(htmlURL, readAccess: paths.root, timeout: 30)
        lap("load")

        let raw: Any?
        do {
            raw = try await web.webView.callAsyncJavaScript(
                "return await window.galleyRender(opts)",
                arguments: ["opts": ["linkNotes": edition.settings.linkNotes]],
                in: nil,
                contentWorld: .page
            )
        } catch {
            let info = (error as NSError).userInfo
            let message = info["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
            let line = info["WKJavaScriptExceptionLineNumber"].map { " (line \($0))" } ?? ""
            throw GalleyError("Laying out the edition failed: \(message)\(line)")
        }
        lap("paginate (Paged.js \((raw as? [String: Any])?["pagedMs"] ?? "?") ms)")
        guard let result = raw as? [String: Any],
              let rects = result["rects"] as? [[String: Double]],
              !rects.isEmpty
        else { throw GalleyError("Laying out the edition failed.") }

        // createPDF captures what is inside the view's bounds, so make the view as
        // tall as the whole paginated document.
        let height = (result["documentHeight"] as? Double) ?? rects.map { $0["y"]! + $0["height"]! }.max()!
        web.resize(to: CGSize(width: 900, height: height))
        try await Task.sleep(for: .milliseconds(100))

        var pages: [Data] = []
        for rect in rects {
            let config = WKPDFConfiguration()
            config.rect = CGRect(x: rect["x"]!, y: rect["y"]!, width: rect["width"]!, height: rect["height"]!)
            pages.append(try await web.webView.pdf(configuration: config))
        }

        lap("capture \(pages.count) pages")
        let pdfURL = folder.appendingPathComponent("edition.pdf")
        try PDFAssembler.join(pages, paper: edition.settings.paper, to: pdfURL)
        lap("assemble")

        var starts: [UUID: Int] = [:]
        for (key, value) in result["starts"] as? [String: Int] ?? [:] {
            let raw = key.hasPrefix("a-") ? String(key.dropFirst(2)) : key
            if let id = UUID(uuidString: raw) { starts[id] = value }
        }
        return RenderResult(pdfURL: pdfURL, pageCount: pages.count, articleStartPages: starts)
    }
}

enum PDFAssembler {
    /// Draws each single-page PDF onto a page of exactly `paper` size. WebKit
    /// produces pages in CSS pixels (96 per inch), so they are scaled to points.
    static func join(_ pages: [Data], paper: PaperSize, to url: URL) throws {
        var mediaBox = CGRect(origin: .zero, size: paper.points)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, [
            kCGPDFContextCreator: "Galley",
        ] as CFDictionary) else { throw GalleyError("Couldn't create the PDF file.") }

        for data in pages {
            guard let provider = CGDataProvider(data: data as CFData),
                  let document = CGPDFDocument(provider),
                  let page = document.page(at: 1)
            else { continue }
            let box = page.getBoxRect(.mediaBox)
            context.beginPDFPage([kCGPDFContextMediaBox: mediaBox] as CFDictionary)
            context.saveGState()
            context.scaleBy(x: mediaBox.width / box.width, y: mediaBox.height / box.height)
            context.translateBy(x: -box.minX, y: -box.minY)
            context.drawPDFPage(page)
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
    }
}

extension OffscreenWebView {
    func resize(to size: CGSize) {
        webView.window?.setContentSize(size)
        webView.frame = CGRect(origin: .zero, size: size)
    }
}
