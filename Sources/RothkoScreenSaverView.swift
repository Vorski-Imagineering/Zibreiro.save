import ScreenSaver

@objc(RothkoScreenSaverView)
final class RothkoScreenSaverView: ScreenSaverView {
    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30.0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func animateOneFrame() {
        // The view is intentionally minimal until the bundled web view is added.
    }
}
