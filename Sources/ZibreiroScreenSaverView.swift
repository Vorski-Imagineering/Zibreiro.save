import AppKit
import Darwin
import Metal
import MetalKit
import QuartzCore
import ScreenSaver

@objc(ZibreiroScreenSaverView)
final class ZibreiroScreenSaverView: ScreenSaverView {
    private static let previewMaximumDimension: CGFloat = 1024
    private static let saverMaximumDimension: CGFloat = 2560

    private let isPreviewMode: Bool
    private var metalView: MTKView?
    private var renderer: MetalRenderer?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var hostIsStopping = false
    private var hostExitScheduled = false

    override init?(frame: NSRect, isPreview: Bool) {
        // legacyScreenSaver has shipped regressions where isPreview is wrong.
        // Aerial and ScreenSaverMinimal both use the tiny Settings frame as the
        // reliable discriminator on affected macOS releases.
        isPreviewMode = frame.width < 400 && frame.height < 300
        super.init(frame: frame, isPreview: isPreviewMode)
        configureInactiveAppearance()
        configureLifecycleObservers()
    }

    required init?(coder: NSCoder) {
        // ScreenSaverView's archive path is only used by older hosts. Treat it
        // conservatively as preview-sized; the regular screen-saver path uses
        // the designated initializer above.
        isPreviewMode = true
        super.init(coder: coder)
        configureInactiveAppearance()
    }

    deinit {
        for observer in lifecycleObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        releaseRenderer()
    }

    override func animateOneFrame() {
        // ScreenSaverView is the sole frame scheduler. MetalKit's own timer is
        // deliberately disabled in configureRenderer().
        guard shouldKeepRenderer else {
            releaseRenderer()
            return
        }
        configureRendererIfNeeded()
        metalView?.draw()
    }

    override func startAnimation() {
        guard !hostIsStopping else { return }
        let isNewStart = !isAnimating
        if isNewStart {
            super.startAnimation()
        }
        guard shouldKeepRenderer else {
            releaseRenderer()
            return
        }
        configureRendererIfNeeded()
        if isNewStart {
            renderer?.startNewComposition()
        }
        metalView?.draw()
    }

    override func stopAnimation() {
        if isAnimating {
            super.stopAnimation()
        }
        releaseRenderer()
    }

    override func viewDidHide() {
        super.viewDidHide()
        // System Settings does not reliably balance startAnimation() with
        // stopAnimation() when its preview is replaced or navigated away from.
        releaseRenderer()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        reconcileRendererWithVisibility()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reconcileRendererWithVisibility()
    }

    override func layout() {
        super.layout()
        metalView?.frame = bounds
        updateDrawableSize()
    }

    private func configureInactiveAppearance() {
        animationTimeInterval = 1.0 / 30.0
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    private var shouldKeepRenderer: Bool {
        guard !hostIsStopping, isAnimating, window != nil else {
            return false
        }

        // The Wallpaper bridge does not expose reliable NSWindow visibility or
        // occlusion state during startup. Use ScreenSaverView's own lifecycle
        // signals here; the willstop host-exit workaround below is the hard
        // guarantee against retained off-screen instances.
        return !isHiddenOrHasHiddenAncestor
            && !visibleRect.isEmpty
    }

    private func configureLifecycleObservers() {
        guard !isPreviewMode else { return }

        // Sonoma and later can omit stopAnimation(), retain every old view,
        // and keep their timers running in the Wallpaper legacy host. This
        // distributed notification is the lifecycle workaround used by Aerial
        // and the AerialScreensaver/ScreenSaverMinimal reference project.
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.screensaver.willstop", "com.apple.screensaver.didstop"] {
            let observer = center.addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                self?.screenSaverHostWillStop()
            }
            lifecycleObservers.append(observer)
        }
    }

    private func reconcileRendererWithVisibility() {
        if shouldKeepRenderer {
            configureRendererIfNeeded()
        } else {
            releaseRenderer()
        }
    }

    private func screenSaverHostWillStop() {
        guard !isPreviewMode else { return }
        hostIsStopping = true
        releaseRenderer()

        guard !hostExitScheduled else { return }
        hostExitScheduled = true

        // The process is a dedicated legacyScreenSaver host. macOS 14+ may
        // leave it alive indefinitely with all old ScreenSaverViews retained.
        // A short delay lets the host finish its exit transition, then process
        // termination provides a hard guarantee that IOSurfaces and GPU heaps
        // cannot survive into the next saver run.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            Darwin.exit(0)
        }
    }

    private func configureRendererIfNeeded() {
        guard metalView == nil, shouldKeepRenderer else { return }

        guard let device = MTLCreateSystemDefaultDevice() else {
            layer?.backgroundColor = NSColor(red: 0.02, green: 0.05, blue: 0.03, alpha: 1).cgColor
            return
        }

        let view = MTKView(frame: bounds, device: device)
        view.autoresizingMask = [.width, .height]
        // The WebGL reference's shader values are display-referred sRGB values.
        // Preserve those values in a float drawable and tag them accordingly.
        view.colorPixelFormat = .rgba16Float
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.framebufferOnly = true
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = isPreviewMode ? 12 : 30
        view.autoResizeDrawable = false
        if let metalLayer = view.layer as? CAMetalLayer {
            // Two buffers are enough for a manually driven 30 FPS saver and
            // bound the largest IOSurface pool MTKView can retain.
            metalLayer.maximumDrawableCount = 2
        }

        updateDrawableSize(for: view)

        do {
            let renderer = try MetalRenderer(device: device, bundle: Bundle(for: ZibreiroScreenSaverView.self))
            addSubview(view)
            updateDrawableSize(for: view)
            renderer.attach(to: view)
            view.delegate = renderer
            metalView = view
            self.renderer = renderer
        } catch {
            view.releaseDrawables()
            view.removeFromSuperview()
            NSLog("Zibreiro screen saver could not create Metal renderer: %@", error.localizedDescription)
            layer?.backgroundColor = NSColor(red: 0.02, green: 0.05, blue: 0.03, alpha: 1).cgColor
        }
    }

    private func updateDrawableSize() {
        guard let metalView else { return }
        updateDrawableSize(for: metalView)
    }

    private func updateDrawableSize(for metalView: MTKView) {
        // The artwork is deliberately soft. A bounded render size is visually
        // equivalent on high-DPI displays while preventing one 5K/6K view from
        // allocating hundreds of megabytes per drawable and pigment texture.
        let maximumDimension = isPreviewMode
            ? Self.previewMaximumDimension
            : Self.saverMaximumDimension
        let nativeSize = metalView.convertToBacking(metalView.bounds).size
        let longestSide = max(nativeSize.width, nativeSize.height)
        guard longestSide > 0 else { return }
        let scale = min(1, maximumDimension / longestSide)
        metalView.drawableSize = CGSize(
            width: max(1, floor(nativeSize.width * scale)),
            height: max(1, floor(nativeSize.height * scale)))
    }

    private func releaseRenderer() {
        // MTKView owns Core Animation drawable pools. Removing the view and
        // releasing its delegate lets the legacy host return both those pools
        // and Zibreiro's offscreen Metal texture while it remains idle.
        let releasedRenderer = renderer
        renderer = nil
        metalView?.delegate = nil
        metalView?.isPaused = true
        releasedRenderer?.shutdown()
        metalView?.releaseDrawables()
        metalView?.removeFromSuperview()
        metalView = nil
    }
}
