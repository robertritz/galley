import AppKit
import UniformTypeIdentifiers

/// Share → Galley. Collects the shared links and hands them to the app through its
/// URL scheme (galley://add?url=…), so the extension needs no access to the library.
/// The links go into the edition you added to last.
final class ShareViewController: NSViewController {
    private let label = NSTextField(labelWithString: "Adding to Galley…")

    override func loadView() {
        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        label.font = .systemFont(ofSize: 13, weight: .medium)
        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 24)
        view = stack
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await share() }
    }

    private func share() async {
        let urls = await sharedURLs()
        guard !urls.isEmpty else {
            label.stringValue = "There’s no link to add."
            try? await Task.sleep(for: .seconds(1.2))
            extensionContext?.cancelRequest(withError: NSError(domain: "Galley", code: 1))
            return
        }
        let scheme = Bundle.main.object(forInfoDictionaryKey: "GalleyURLScheme") as? String ?? "galley"
        var components = URLComponents()
        components.scheme = scheme
        components.host = "add"
        components.queryItems = urls.map { URLQueryItem(name: "url", value: $0.absoluteString) }
        if let url = components.url {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false  // stay where you are; Galley fetches in the background
            _ = try? await NSWorkspace.shared.open(url, configuration: configuration)
        }
        label.stringValue = urls.count == 1 ? "Added to Galley" : "Added \(urls.count) links to Galley"
        try? await Task.sleep(for: .seconds(0.8))
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Links from the shared items: web URLs directly, or any found in shared text.
    private func sharedURLs() async -> [URL] {
        var found: [URL] = []
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) {
                if let url = item as? URL { found.append(url) }
                else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { found.append(url) }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                found.append(contentsOf: Self.links(in: text))
            }
        }
        var seen = Set<URL>()
        return found.filter { ($0.scheme == "http" || $0.scheme == "https") && seen.insert($0).inserted }
    }

    private static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url)
    }
}
