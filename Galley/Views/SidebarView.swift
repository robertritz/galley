import GalleyCore
import SwiftData
import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Environment(Library.self) private var library
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Edition.number, order: .reverse) private var editions: [Edition]
    @Query private var articles: [Article]

    var body: some View {
        List(selection: $selection) {
            Section("Next Edition") {
                ForEach(editions.filter { $0.state == .open }) { edition in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(edition.title, systemImage: "tray.full")
                        Text(closesText(edition))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 26)
                    }
                    .badge(edition.articles.count)
                    .tag(SidebarItem.edition(edition.id))
                }
            }

            let past = editions.filter { $0.state != .open }
            if !past.isEmpty {
                Section("Editions") {
                    ForEach(past) { edition in
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(edition.title)
                                Text(edition.dateLabel).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: edition.state == .printed ? "checkmark.circle" : "newspaper")
                        }
                        .tag(SidebarItem.edition(edition.id))
                        .contextMenu {
                            if edition.state == .closed {
                                Button("Mark as Printed") { library.markPrinted(edition) }
                            }
                            Button("Delete Edition…", role: .destructive) { confirmDelete(edition) }
                        }
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
                openWindow(id: "browser", value: BrowserRequest())
            } label: {
                Label("Sign in to Sites…", systemImage: "person.badge.key")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(10)
            .help("Open Galley's browser to sign in to sites you subscribe to")
        }
    }

    private func closesText(_ edition: Edition) -> String {
        guard let end = edition.periodEnd else { return "Closes when you close it" }
        return "Closes " + end.formatted(.relative(presentation: .named))
    }

    private func confirmDelete(_ edition: Edition) {
        let alert = NSAlert()
        alert.messageText = "Delete \(edition.title)?"
        alert.informativeText = "Its \(edition.articles.count) articles and the PDF will be removed. This can't be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            if selection == .edition(edition.id) { selection = nil }
            library.delete(edition)
        }
    }
}
