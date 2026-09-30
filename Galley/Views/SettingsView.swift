import GalleyCore
import SwiftUI
import WebKit

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Edition", systemImage: "newspaper") { EditionSettings() }
            Tab("Printing", systemImage: "printer") { PrintingSettings() }
            Tab("Library", systemImage: "books.vertical") { LibrarySettings() }
        }
        .frame(width: 500)
        .scenePadding()
    }
}

private struct EditionSettings: View {
    @Environment(Library.self) private var library
    @AppStorage(Pref.masthead) private var masthead = "Galley"
    @AppStorage(Pref.cadenceKind) private var kind = Cadence.Kind.weekly.rawValue
    @AppStorage(Pref.cadenceWeekday) private var weekday = 1
    @AppStorage(Pref.cadenceMonthDay) private var monthDay = 1

    var body: some View {
        Form {
            TextField("Magazine name:", text: $masthead, prompt: Text("Galley"))
            Text("Printed as the masthead on the cover of every edition.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("New edition:", selection: $kind) {
                ForEach(Cadence.Kind.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)

            switch Cadence.Kind(rawValue: kind) ?? .weekly {
            case .weekly:
                Picker("Closes on:", selection: $weekday) {
                    ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
                }
            case .monthly:
                Picker("Closes on day:", selection: $monthDay) {
                    ForEach(1...28, id: \.self) { Text("\($0)").tag($0) }
                }
            case .daily, .manual:
                EmptyView()
            }
            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: kind) { library.cadenceChanged() }
        .onChange(of: weekday) { library.cadenceChanged() }
        .onChange(of: monthDay) { library.cadenceChanged() }
    }

    private var explanation: String {
        let cadence = Pref.cadence
        switch cadence {
        case .manual:
            return "The edition stays open until you press Close Edition."
        default:
            let next = cadence.nextClose(after: .now).map { $0.formatted(date: .complete, time: .omitted) } ?? ""
            return "At midnight the current edition closes, is laid out, and Galley lets you know it's ready to print. Next: \(next)."
        }
    }
}

private struct PrintingSettings: View {
    @AppStorage(Pref.paper) private var paper = PaperSize.regionDefault.rawValue
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
