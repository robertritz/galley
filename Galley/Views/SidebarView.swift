import GalleyCore
import SwiftData
import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Binding var naming: EditionNaming
    @Environment(Library.self) private var library
    @Query(sort: \Edition.number, order: .reverse) private var editions: [Edition]
    @Query private var articles: [Article]

    var body: some View {
        List(selection: $selection) {
            Section("Editions") {
                ForEach(editions.filter { $0.state == .draft }) { edition in
                    row(edition)
                }
            }

            let printed = editions.filter { $0.state == .printed }
            if !printed.isEmpty {
                Section("Printed") {
                    ForEach(printed) { edition in
                        row(edition)
                    }
                }
            }

            Section("Library") {
                Label("All Articles", systemImage: "doc.text")
                    .badge(articles.count)
                    .tag(SidebarItem.allArticles)
                let problems = articles.filter { $0.status.isProblem }.count
                Label("Needs Attention", systemImage: "exclamationmark.triangle")
                    .badge(problems)
                    .tag(SidebarItem.needsAttention)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button {
                naming = EditionNaming(isPresented: true)
            } label: {
                Label("New Edition", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .help("Make a new edition (⌘N)")
            .padding(10)
        }
    }

    private func row(_ edition: Edition) -> some View {
        // Two-line row with the icon centred on both lines, like Mail's mailboxes.
        HStack(spacing: 8) {
            SidebarIcon(systemName: edition.state == .printed ? "checkmark.circle" : "doc.text.image")
            VStack(alignment: .leading, spacing: 1) {
                Text(edition.displayName).lineLimit(1)
                Text(subtitle(edition)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .badge(edition.articles.count)
        .tag(SidebarItem.edition(edition.id))
        .dropDestination(for: URL.self) { urls, _ in
            // Drop links from a browser straight onto an edition.
            let web = urls.filter { $0.scheme == "http" || $0.scheme == "https" }
            guard !web.isEmpty else { return false }
            library.add(web, to: edition)
            return true
        }
        .contextMenu {
            Button("Rename…") { naming = .rename(edition) }
            if edition.state == .draft {
                Button("Mark as Printed") { library.markPrinted(edition) }
            } else {
                Button("Move Back to Editions") { library.markDraft(edition) }
            }
            Divider()
            Button("Delete Edition…", role: .destructive) { confirmDelete(edition) }
        }
    }

    private func subtitle(_ edition: Edition) -> String {
        var parts: [String] = []
        if !edition.name.isEmpty { parts.append("No. \(edition.number)") }
        if let printed = edition.printedAt {
            parts.append(printed.formatted(date: .abbreviated, time: .omitted))
        } else if let pages = edition.pageCount, !edition.articles.isEmpty {
            parts.append("\(pages) pages")
        } else if edition.articles.isEmpty {
            parts.append("Empty")
        }
        return parts.joined(separator: " · ")
    }

    private func confirmDelete(_ edition: Edition) {
        let alert = NSAlert()
        alert.messageText = "Delete \(edition.displayName)?"
        alert.informativeText = edition.articles.isEmpty
            ? "This can't be undone."
            : "Its \(edition.articles.count) articles and the PDF will be removed. This can't be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            if selection == .edition(edition.id) { selection = nil }
            library.delete(edition)
        }
    }
}

/// An accent-coloured sidebar icon that turns white on a selected row, as built-in
/// sidebar labels do. (A plain tint would vanish into the blue selection.)
private struct SidebarIcon: View {
    let systemName: String
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Image(systemName: systemName)
            .font(.body)
            .foregroundStyle(prominence == .increased ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
            .frame(width: 20)
    }
}
