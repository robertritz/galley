import GalleyCore
import SwiftUI
import WebKit

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "newspaper") { GeneralSettings() }
            Tab("Printing", systemImage: "printer") { PrintingSettings() }
            Tab("Library", systemImage: "books.vertical") { LibrarySettings() }
        }
        .frame(width: 500)
        .scenePadding()
    }
}

private struct GeneralSettings: View {
    @AppStorage(Pref.masthead) private var masthead = "Galley"
    @AppStorage(Pref.readerName) private var readerName = ""

    var body: some View {
        Form {
            TextField("Magazine name:", text: $masthead, prompt: Text("Galley"))
            Text("Printed as the masthead on the cover of every edition.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Your name:", text: $readerName, prompt: Text("Optional"))
            Text("Printed under the masthead, like the name on a subscriber's copy. Leave it empty to show the number of stories instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PrintingSettings: View {
    @AppStorage(Pref.paper) private var paper = PaperSize.regionDefault.rawValue
    @AppStorage(Pref.columns) private var columns = ColumnLayout.two.rawValue
    @AppStorage(Pref.imageMode) private var imageMode = ImageMode.color.rawValue
    @AppStorage(Pref.linkNotes) private var linkNotes = true

    var body: some View {
        Form {
            Picker("Paper size:", selection: $paper) {
                ForEach(PaperSize.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            Text("Editions print on one side of the page.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Layout:", selection: $columns) {
                ForEach(ColumnLayout.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            .pickerStyle(.radioGroup)

            Picker("Images:", selection: $imageMode) {
                ForEach(ImageMode.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            Text("Greyscale saves colour ink; No images makes the shortest editions.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Print links as numbered notes at the end of each article", isOn: $linkNotes)
        }
    }
}

private struct LibrarySettings: View {
    @Environment(Library.self) private var library
    @State private var confirmSignOut = false

    var body: some View {
        Form {
            LabeledContent("Library folder:") {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([library.paths.root]) }
            }
            Text(library.paths.root.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            LabeledContent("Site logins:") {
                Button("Sign Out of All Sites…") { confirmSignOut = true }
            }
            Text("Sites you sign into with Galley's browser stay signed in so articles can be fetched in full. Sign out to remove those cookies.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog("Sign out of every site in Galley's browser?", isPresented: $confirmSignOut) {
            Button("Sign Out", role: .destructive) {
                Task {
                    await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
                }
            }
        }
    }
}
