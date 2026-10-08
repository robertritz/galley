import GalleyCore
import SwiftData
import SwiftUI

@main
struct GalleyApp: App {
    @State private var library = Library()
    let container: ModelContainer

    init() {
        Pref.registerDefaults()
        _ = Updater.shared
        do {
            // Keep the database with the article files, not in a shared default location.
            let root = GalleyPaths.default.root
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let config = ModelConfiguration(url: root.appendingPathComponent("Galley.store"))
            container = try ModelContainer(for: Article.self, Edition.self, configurations: config)
        } catch {
            fatalError("Couldn't open Galley's library: \(error)")
        }
    }

    var body: some Scene {
        Window("Galley", id: "main") {
            ContentView()
                .environment(library)
                .onAppear { library.start(context: container.mainContext) }
        }
        .modelContainer(container)
        .defaultSize(width: 1280, height: 820)
        .commands { GalleyCommands() }

        WindowGroup("Browser", id: "browser", for: BrowserRequest.self) { $request in
            BrowserView(request: request ?? BrowserRequest())
                .environment(library)
                .modelContainer(container)
        }
        .defaultSize(width: 1100, height: 850)

        Settings {
            SettingsView()
                .environment(library)
        }
    }
}

/// Opens the in-app browser, optionally at a URL, optionally to re-capture an article.
struct BrowserRequest: Codable, Hashable {
    var url: URL?
    var articleID: UUID?
}

struct GalleyCommands: Commands {
    @FocusedValue(\.galleyActions) private var actions

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesButton()
        }
        CommandGroup(replacing: .newItem) {
            Button("New Edition…") { actions?.newEdition() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)
            Button("Add Link…") { actions?.addLink() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(actions == nil)
            Button("Open Browser…") { actions?.openBrowser() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(actions == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button("Print Edition…") { actions?.printEdition() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(actions?.canPrint != true)
            Button("Export PDF…") { actions?.exportPDF() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(actions?.canPrint != true)
        }
    }
}

/// Menu commands implemented by the main window.
struct GalleyActions {
    var newEdition: () -> Void
    var addLink: () -> Void
    var openBrowser: () -> Void
    var printEdition: () -> Void
    var exportPDF: () -> Void
    var canPrint: Bool
}

extension FocusedValues {
    @Entry var galleyActions: GalleyActions?
}
