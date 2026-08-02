import AppKit
import Metal
import MetalKit
import ScreenSaver

@objc(ZibreiroScreenSaverView)
final class ZibreiroScreenSaverView: ScreenSaverView {
    // System Settings can keep a preview ScreenSaverView animating in its
    // compatibility host long after its thumbnail is no longer on screen.
    // A preview never needs a native 4K/5K drawable, which would otherwise
    // retain several large Core Animation/Metal surface pools.
    private let isPreviewMode: Bool
    private var metalView: MTKView?
    private var renderer: MetalRenderer?

    override init?(frame: NSRect, isPreview: Bool) {
        isPreviewMode = isPreview
        super.init(frame: frame, isPreview: isPreview)
        configureInactiveAppearance()
    }

    required init?(coder: NSCoder) {
        // ScreenSaverView's archive path is only used by older hosts. Treat it
        // conservatively as preview-sized; the regular screen-saver path uses
        // the designated initializer above.
        isPreviewMode = true
        super.init(coder: coder)
        configureInactiveAppearance()
    }

    override func animateOneFrame() {
        // ScreenSaverView is the sole frame scheduler. MetalKit's own timer is
        // deliberately disabled in configureRenderer().
        metalView?.draw()
    }

    override func startAnimation() {
        configureRendererIfNeeded()
        super.startAnimation()
        renderer?.startNewComposition()
        metalView?.draw()
    }

    override func stopAnimation() {
        super.stopAnimation()
        releaseRenderer()
    }

    override func layout() {
        super.layout()
        metalView?.frame = bounds
        updatePreviewDrawableSize()
    }

    private func configureInactiveAppearance() {
        animationTimeInterval = 1.0 / 30.0
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    private func configureRendererIfNeeded() {
        guard metalView == nil else { return }

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
        view.autoResizeDrawable = !isPreviewMode

        do {
            let renderer = try MetalRenderer(device: device, bundle: Bundle(for: ZibreiroScreenSaverView.self))
            renderer.attach(to: view)
            view.delegate = renderer
            addSubview(view)
            metalView = view
            self.renderer = renderer
            updatePreviewDrawableSize()
        } catch {
            NSLog("Zibreiro screen saver could not create Metal renderer: %@", error.localizedDescription)
            layer?.backgroundColor = NSColor(red: 0.02, green: 0.05, blue: 0.03, alpha: 1).cgColor
        }
    }

    private func updatePreviewDrawableSize() {
        guard isPreviewMode, let metalView else { return }

        // 1,024 pixels across preserves the artwork in the Settings preview,
        // but turns a possible 5K RGBA32Float pigment allocation into roughly
        // 16 MB instead of roughly 236 MB. MTKView owns the corresponding
        // drawable pool, so this also prevents the host's multi-gigabyte
        // IOSurface allocation while it is idling in Settings.
        let nativeSize = metalView.convertToBacking(metalView.bounds).size
        let longestSide = max(nativeSize.width, nativeSize.height)
        guard longestSide > 0 else { return }
        let scale = min(1, 1024 / longestSide)
        metalView.drawableSize = CGSize(
            width: max(1, floor(nativeSize.width * scale)),
            height: max(1, floor(nativeSize.height * scale)))
    }

    private func releaseRenderer() {
        // MTKView owns Core Animation drawable pools. Removing the view and
        // releasing its delegate lets the legacy host return both those pools
        // and Zibreiro's offscreen Metal texture while it remains idle.
        metalView?.delegate = nil
        metalView?.isPaused = true
        metalView?.removeFromSuperview()
        metalView = nil
        renderer = nil
    }
}
