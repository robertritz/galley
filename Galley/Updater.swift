import Combine
import Sparkle
import SwiftUI

/// Keeps Galley up to date with Sparkle: it reads `appcast.xml` from the repo and
/// installs releases signed with Galley's update key. Only release builds check,
/// so builds run from Xcode never replace themselves.
final class Updater {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController
    private let delegate = UpdaterDelegate()
    var updater: SPUUpdater { controller.updater }

    private init() {
        #if DEBUG
        let start = false
        #else
        let start = true
        #endif
        controller = SPUStandardUpdaterController(startingUpdater: start, updaterDelegate: delegate, userDriverDelegate: nil)
    }
}

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    /// `GALLEY_FEED_URL` points a build at another appcast, for testing updates.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        ProcessInfo.processInfo.environment["GALLEY_FEED_URL"]
    }
}

/// Galley → Check for Updates…
struct CheckForUpdatesButton: View {
    @StateObject private var model = CheckForUpdatesModel(updater: Updater.shared.updater)

    var body: some View {
        Button("Check for Updates…") { Updater.shared.updater.checkForUpdates() }
            .disabled(!model.canCheckForUpdates)
    }
}

private final class CheckForUpdatesModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }
}
