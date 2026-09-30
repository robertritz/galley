import AppKit
import GalleyCore
import PDFKit
import SwiftUI

/// The detail column: the laid-out edition as it will print.
struct EditionPreview: View {
    let edition: Edition
    let selectedArticleID: UUID?
    @Environment(Library.self) private var library

    // Read so that changing a setting re-renders the preview.
    @AppStorage(Pref.paper) private var paper = PaperSize.regionDefault.rawValue
    @AppStorage(Pref.imageMode) private var imageMode = ImageMode.color.rawValue
    @AppStorage(Pref.linkNotes) private var linkNotes = true
    @AppStorage(Pref.masthead) private var masthead = "Galley"
    @AppStorage(Pref.cadenceKind) private var cadenceKind = Cadence.Kind.weekly.rawValue

    @State private var document: PDFDocument?
    @State private var loadedModified: Date?

    private var renderTrigger: String { "\(edition.id)|\(edition.contentVersion)|\(Pref.renderKey)" }
    private var isRendering: Bool { library.rendering.contains(edition.id) }
    private var hasPendingFetches: Bool { edition.articles.contains { $0.status.isWorking } }

    var body: some View {
        ZStack {
            if let document {
                PDFKitView(document: document, page: targetPage)
            } else if let error = library.renderErrors[edition.id] {
                ContentUnavailableView("No Preview", systemImage: "doc.richtext", description: Text(error))
            } else if edition.printableArticles.isEmpty {
                ContentUnavailableView("Nothing to Print Yet", systemImage: "doc.richtext",
                                       description: Text(hasPendingFetches ? "Articles are still being fetched." : "Add articles and they'll be laid out here."))
            } else {
                ProgressView("Laying out \(edition.title)…")
            }
        }
        .overlay(alignment: .top) {
            if isRendering && document != nil {
                Label("Updating layout…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: .capsule)
                    .padding(.top, 10)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await EditionOutput.export(edition, library: library) }
                } label: { Label("Export PDF", systemImage: "square.and.arrow.up") }
                    .disabled(edition.printableArticles.isEmpty)
                    .help("Save the edition as a PDF")
                Button {
                    Task { await EditionOutput.print(edition, library: library) }
                } label: { Label("Print", systemImage: "printer") }
                    .disabled(edition.printableArticles.isEmpty)
                    .help("Print the edition (⌘P)")
            }
        }
        .task(id: renderTrigger) {
            loadExisting()
            guard edition.needsRender(settings: Pref.renderKey), !edition.printableArticles.isEmpty else { return }
            // Wait for edits to settle before laying out again.
            try? await Task.sleep(for: .seconds(document == nil ? 0.2 : 1.2))
            guard !Task.isCancelled else { return }
            await library.render(edition)
            loadExisting()
        }
        .onChange(of: library.rendering) { loadExisting() }
    }

    private var targetPage: Int? {
        guard let id = selectedArticleID else { return nil }
        return edition.articles.first { $0.id == id }?.startPage
    }

    private func loadExisting() {
        guard let url = library.pdfURL(for: edition) else {
            document = nil
            loadedModified = nil
            return
        }
        // Reload only when the file on disk is newer than what's shown.
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if document == nil || modified != loadedModified {
            document = PDFDocument(url: url)
            loadedModified = modified
        }
    }
}

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    var page: Int?

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.pageShadowsEnabled = true
        view.backgroundColor = .underPageBackgroundColor
        view.document = document
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            let current = view.currentPage.flatMap { view.document?.index(for: $0) }
            view.document = document
            if let current, let restored = document.page(at: min(current, document.pageCount - 1)) {
                view.go(to: restored)
            }
        }
        if let page, page != context.coordinator.lastPage, let target = document.page(at: page - 1) {
            view.go(to: target)
        }
        context.coordinator.lastPage = page
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastPage: Int?
    }
}

/// Printing and exporting an edition's PDF, rendering it first if it's out of date.
enum EditionOutput {
    static func ensureRendered(_ edition: Edition, library: Library) async -> URL? {
        if edition.needsRender(settings: Pref.renderKey) || library.pdfURL(for: edition) == nil {
            await library.render(edition)
        }
        if let error = library.renderErrors[edition.id] {
            let alert = NSAlert()
            alert.messageText = "Galley couldn't lay out this edition"
            alert.informativeText = error
            alert.runModal()
            return nil
        }
        return library.pdfURL(for: edition)
    }

    static func print(_ edition: Edition, library: Library) async {
        guard let url = await ensureRendered(edition, library: library), let document = PDFDocument(url: url) else { return }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.paperSize = Pref.renderSettings.paper.points
        info.orientation = .portrait
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.jobDisposition = .spool
        guard let operation = document.printOperation(for: info, scalingMode: .pageScaleNone, autoRotate: false) else { return }
        operation.jobTitle = "\(Pref.mastheadName) \(edition.title)"
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window = NSApp.mainWindow {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    static func export(_ edition: Edition, library: Library) async {
        guard let url = await ensureRendered(edition, library: library) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(Pref.mastheadName) \(edition.number) – \(edition.dateLabel).pdf"
            .replacingOccurrences(of: "/", with: "-")
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
