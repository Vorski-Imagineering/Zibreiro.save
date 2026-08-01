import ScreenSaver
import WebKit

@objc(RothkoScreenSaverView)
final class RothkoScreenSaverView: ScreenSaverView {
    private let webView: WKWebView

    override init?(frame: NSRect, isPreview: Bool) {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30.0
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
        loadBundledHTML()
    }

    required init?(coder: NSCoder) {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init(coder: coder)
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
        loadBundledHTML()
    }

    override func animateOneFrame() {
    }

    override func layout() {
        super.layout()
        webView.frame = bounds
    }

    private func loadBundledHTML() {
        guard let htmlURL = Bundle(for: RothkoScreenSaverView.self).url(forResource: "index", withExtension: "html") else {
            return
        }

        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }
}
