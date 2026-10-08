import AppKit
import SwiftUI

/// Shown on first launch: name the magazine and, if they like, put the reader's name on the cover.
/// Both can be changed later in Settings.
struct SetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Pref.masthead) private var masthead = "Galley"
    @AppStorage(Pref.readerName) private var readerName = ""
    @AppStorage(Pref.didSetUp) private var didSetUp = false

    @State private var name = ""
    @State private var reader = ""

    private var shownMasthead: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Galley" : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Galley")
                        .font(.title2.bold())
                    Text("Give your magazine a name. You can change this later in Settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            coverPreview

            Form {
                TextField("Magazine name:", text: $name, prompt: Text("Galley"))
                TextField("Your name:", text: $reader, prompt: Text("Optional"))
                Text("Printed on the cover, like the name on a subscriber's copy. Leave it empty to show the number of stories instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Start Reading") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .interactiveDismissDisabled()
        .onAppear {
            name = masthead
            reader = readerName.isEmpty ? NSFullUserName() : readerName
        }
    }

    /// The top of a cover, as it will print.
    private var coverPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(shownMasthead)
                .font(.system(size: 44, weight: .heavy, design: .serif))
                .kerning(-1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Rectangle().frame(height: 0.75)
            HStack {
                Text("No. 1")
                Spacer()
                Text(Date.now.formatted(date: .long, time: .omitted))
                Spacer()
                let trimmed = reader.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    Text("6 stories")
                } else {
                    Text(trimmed).font(.system(size: 11, design: .serif).italic())
                }
            }
            .font(.system(size: 9, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.9)
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(.white, in: .rect(cornerRadius: 4))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }

    private func save() {
        masthead = name.trimmingCharacters(in: .whitespaces)
        readerName = reader.trimmingCharacters(in: .whitespaces)
        didSetUp = true
        dismiss()
    }
}
