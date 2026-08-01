import ScreenSaver
import WebKit

@objc(RothkoScreenSaverView)
final class RothkoScreenSaverView: ScreenSaverView, WKNavigationDelegate {
    private let webView: WKWebView
    private var hasLoadedBundledHTML = false

    override init?(frame: NSRect, isPreview: Bool) {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30.0
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        addSubview(webView)
        webView.frame = bounds
    }

    required init?(coder: NSCoder) {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init(coder: coder)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        addSubview(webView)
        webView.frame = bounds
    }

    override func animateOneFrame() {
    }

    override func layout() {
        super.layout()
        webView.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        webView.frame = bounds
        if window != nil {
            loadBundledHTML()
        }
    }

    private func loadBundledHTML() {
        guard !hasLoadedBundledHTML else { return }
        guard let htmlURL = Bundle(for: RothkoScreenSaverView.self).url(forResource: "index", withExtension: "html") else {
            return
        }

        hasLoadedBundledHTML = true
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("Rothko screen saver failed to load bundled HTML: %@", error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("Rothko screen saver failed to start bundled HTML: %@", error.localizedDescription)
    }
}
