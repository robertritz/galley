import AppKit
import SwiftUI

struct AddLinkSheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var urls: [URL] { LinkParser.urls(in: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add to the Next Edition")
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
            HStack {
                Text(urls.isEmpty ? "No links found" : "\(urls.count) \(urls.count == 1 ? "link" : "links")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    library.add(urls)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(urls.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            // Start with whatever links are on the clipboard.
            if let clip = NSPasteboard.general.string(forType: .string), !LinkParser.urls(in: clip).isEmpty {
                text = clip.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
            }
        }
    }
}
