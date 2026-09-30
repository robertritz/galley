import GalleyCore
import SwiftData
import SwiftUI
import WebKit

/// Galley's own browser. Sign in to sites you subscribe to here: the cookies are
/// shared with the article fetcher. Also used to capture articles by hand when
/// automatic fetching fails.
struct BrowserView: View {
    let request: BrowserRequest
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Query private var articles: [Article]

    @State private var page = BrowserPage()
    @State private var address = ""
    @State private var capturing = false
    @State private var captured = false

    private var fixing: Article? {
        request.articleID.flatMap { id in articles.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let fixing {
                banner("Deal with any login or pop-up, then press **Add to Galley** to replace “\(fixing.title)”.")
            } else if request.url == nil && page.url == nil {
                banner("Sign in to sites you subscribe to. Galley remembers the login and uses it when fetching articles.")
            }
            BrowserWebView(page: page)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { page.webView.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                    .disabled(!page.canGoBack)
                Button { page.webView.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                    .disabled(!page.canGoForward)
            }
            ToolbarItem(placement: .principal) {
                TextField("Address", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 420)
                    .onSubmit(go)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if page.isLoading { ProgressView().controlSize(.small) }
                Button {
                    Task { await capture() }
                } label: {
                    Label(captured ? "Added" : "Add to Galley", systemImage: captured ? "checkmark" : "plus.rectangle.on.rectangle")
                }
                .disabled(page.url == nil || capturing)
                .help("Add the article on this page to the next edition")
            }
        }
        .navigationTitle(page.title.isEmpty ? "Galley Browser" : page.title)
        .onAppear {
            if let url = request.url {
                address = url.absoluteString
                page.webView.load(URLRequest(url: url))
            }
        }
        .onChange(of: page.url) { address = page.url?.absoluteString ?? address; captured = false }
    }

    private func banner(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.yellow.opacity(0.18))
    }

    private func go() {
        var text = address.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if !text.contains("://") { text = text.contains(".") && !text.contains(" ") ? "https://\(text)" : "https://duckduckgo.com/?q=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text)" }
        if let url = URL(string: text) { page.webView.load(URLRequest(url: url)) }
    }

    private func capture() async {
        capturing = true
        await library.capture(from: page.webView, replacing: fixing)
        capturing = false
        captured = true
        if fixing != nil { dismiss() }
    }
}

@Observable
final class BrowserPage: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    var url: URL?
    var title = ""
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    private var observations: [NSKeyValueObservation] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = WebIdentity.userAgent
        super.init()
        webView.navigationDelegate = self
        observations = [
            webView.observe(\.url) { [weak self] web, _ in Task { @MainActor in self?.url = web.url } },
            webView.observe(\.title) { [weak self] web, _ in Task { @MainActor in self?.title = web.title ?? "" } },
            webView.observe(\.isLoading) { [weak self] web, _ in Task { @MainActor in self?.isLoading = web.isLoading } },
            webView.observe(\.canGoBack) { [weak self] web, _ in Task { @MainActor in self?.canGoBack = web.canGoBack } },
            webView.observe(\.canGoForward) { [weak self] web, _ in Task { @MainActor in self?.canGoForward = web.canGoForward } },
        ]
    }
}

struct BrowserWebView: NSViewRepresentable {
    let page: BrowserPage
    func makeNSView(context: Context) -> WKWebView { page.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
