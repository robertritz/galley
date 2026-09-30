import AppKit
import WebKit

public enum WebIdentity {
    /// Safari's user agent, so sites serve the same page a reader would get. The
    /// in-app browser uses it too: some sites tie a login to the browser that made it.
    public static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
}

/// A WKWebView hosted in an invisible window.
///
/// WebKit throttles timers and skips layout for views that are not in a window,
/// which breaks lazy-loading pages and Paged.js. Hosting the view in a real (but
/// transparent, off-screen) window avoids that.
@MainActor
final class OffscreenWebView: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private let window: NSWindow
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    init(size: CGSize = CGSize(width: 1100, height: 1400), dataStore: WKWebsiteDataStore = .default()) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.suppressesIncrementalRendering = false

        webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
        webView.customUserAgent = OffscreenWebView.userAgent

        window = NSWindow(
            contentRect: CGRect(x: -20000, y: -20000, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.alphaValue = 0.01
        window.contentView = webView
        super.init()
        webView.navigationDelegate = self
        window.orderFrontRegardless()
    }

    static var userAgent: String { WebIdentity.userAgent }

    func close() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        window.orderOut(nil)
        window.contentView = nil
    }

    /// Loads a web page. Slow pages are not an error: after `timeout` Galley
    /// works with whatever has loaded so far.
    func load(_ url: URL, timeout: TimeInterval) async throws {
        try await navigate(timeout: timeout, timeoutIsError: false) {
            self.webView.load(URLRequest(url: url, timeoutInterval: timeout))
        }
    }

    func loadFile(_ url: URL, readAccess: URL, timeout: TimeInterval) async throws {
        try await navigate(timeout: timeout, timeoutIsError: true) {
            self.webView.loadFileURL(url, allowingReadAccessTo: readAccess)
        }
    }

    private func navigate(timeout: TimeInterval, timeoutIsError: Bool, start: () -> Void) async throws {
        let timer = Task { @MainActor [weak self] in
            try await Task.sleep(for: .seconds(timeout))
            self?.finishNavigation(timeoutIsError ? .failure(GalleyError("The page took too long to load.")) : .success(()))
        }
        defer { timer.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navigationContinuation = continuation
            start()
        }
    }

    private func finishNavigation(_ result: Result<Void, Error>) {
        guard let continuation = navigationContinuation else { return }
        navigationContinuation = nil
        continuation.resume(with: result)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishNavigation(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    private func fail(_ error: Error) {
        // A page replacing itself (JavaScript redirect) cancels the first navigation.
        // The next navigation will finish or fail on its own.
        if (error as NSError).code == NSURLErrorCancelled { return }
        finishNavigation(.failure(error))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if let http = navigationResponse.response as? HTTPURLResponse, navigationResponse.isForMainFrame, http.statusCode >= 400 {
            finishNavigation(.failure(GalleyError("The site answered with an error (HTTP \(http.statusCode)).")))
            return .cancel
        }
        return .allow
    }
}
