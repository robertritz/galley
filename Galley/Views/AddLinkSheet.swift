import AppKit
import SwiftData
import SwiftUI

struct AddLinkSheet: View {
    /// The edition on screen when the sheet opened, if any.
    var target: Edition?
    var onAdd: (Edition) -> Void = { _ in }

    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Edition.number, order: .reverse) private var editions: [Edition]
    @State private var text = ""
    @State private var editionID: UUID?

    private var urls: [URL] { LinkParser.urls(in: text) }
    private var drafts: [Edition] { editions.filter { $0.state == .draft } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Links")
                .font(.headline)
            Text("Paste one or more links. Each one becomes an article.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background, in: .rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            Picker("Add to:", selection: $editionID) {
                ForEach(target?.state == .printed ? [target!] + drafts : drafts) { edition in
                    Text(edition.displayName).tag(Optional(edition.id))
                }
                Divider()
                Text("New Edition").tag(UUID?.none)
            }
            HStack {
                Text(urls.isEmpty ? "No links found" : "\(urls.count) \(urls.count == 1 ? "link" : "links")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    let edition = editions.first { $0.id == editionID } ?? library.createEdition()
                    onAdd(library.add(urls, to: edition))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(urls.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            editionID = (target ?? library.targetEdition()).id
            // Start with whatever links are on the clipboard.
            if let clip = NSPasteboard.general.string(forType: .string), !LinkParser.urls(in: clip).isEmpty {
                text = clip.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
            }
        }
    }
}
