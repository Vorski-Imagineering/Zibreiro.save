import Foundation
import Metal
import MetalKit
import OSLog
import simd

final class MetalRenderer: NSObject, MTKViewDelegate {
    private static let maximumPigmentDimension = 2560
    private static let logger = Logger(subsystem: "com.example.Zibreiro", category: "metal")

    // Names are the source of truth. The numeric value only crosses the
    // Swift/Metal boundary in the fixed-layout uniform buffer.
    private enum Scenario: CaseIterable {
        case originalForms
        case twoBands
        case warmCoolHorizon
        case stackedStrata
        case smokyCircle

        var slug: String {
            switch self {
            case .originalForms: return "original-forms"
            case .twoBands: return "two-bands"
            case .warmCoolHorizon: return "warm-cool-horizon"
            case .stackedStrata: return "stacked-strata"
            case .smokyCircle: return "smoky-circle"
            }
        }

        var shaderValue: Float {
            switch self {
            case .originalForms: return 0
            case .twoBands: return 1
            case .warmCoolHorizon: return 2
            case .stackedStrata: return 3
            case .smokyCircle: return 4
            }
        }
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pigmentPipeline: MTLRenderPipelineState
    private let outputPipeline: MTLRenderPipelineState
    private let blueNoiseTexture: MTLTexture
    private var pigmentTexture: MTLTexture?
    private var lastCommandBuffer: MTLCommandBuffer?
    private var drawableSize = MTLSize(width: 0, height: 0, depth: 1)
    private var startedAt = ProcessInfo.processInfo.systemUptime
    private var uniforms: ZibreiroUniforms
    private var reportedMissingPigmentTexture = false
    private var reportedMissingRenderPass = false
    private var reportedMissingDrawable = false
    private var reportedMissingCommandBuffer = false
    private var submittedFrameCount: UInt64 = 0
    private let completionLock = NSLock()
    private var reportedFirstCompletion = false

    init(device: MTLDevice, bundle: Bundle) throws {
        precondition(MemoryLayout<ZibreiroUniforms>.stride == 192, "Swift/Metal ZibreiroUniforms layout changed")
        self.device = device
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        Self.logger.notice("renderer init build=\(build, privacy: .public) device=\(device.name, privacy: .public) uniformStride=\(MemoryLayout<ZibreiroUniforms>.stride)")
        guard let libraryURL = bundle.url(forResource: "default", withExtension: "metallib") else {
            Self.logger.error("default.metallib missing from bundle=\(bundle.bundlePath, privacy: .public)")
            throw RendererError.metalLibraryMissing
        }
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(URL: libraryURL)
        } catch {
            Self.logger.error("could not load metallib url=\(libraryURL.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw error
        }
        guard let commandQueue = device.makeCommandQueue(),
              let vertex = library.makeFunction(name: "fullscreenVertex"),
              let pigment = library.makeFunction(name: "pigmentFragment"),
              let output = library.makeFunction(name: "outputFragment") else {
            Self.logger.error("Metal queue or required shader function is unavailable")
            throw RendererError.metalSetupFailed
        }
        self.commandQueue = commandQueue

        let pigmentDescriptor = MTLRenderPipelineDescriptor()
        pigmentDescriptor.vertexFunction = vertex
        pigmentDescriptor.fragmentFunction = pigment
        // Keep the pigment field in full 32-bit float through both paint and
        // tone/output passes. The 8-bit display drawable is unavoidable, so
        // quantization happens exactly once, after stable dithering.
        pigmentDescriptor.colorAttachments[0].pixelFormat = .rgba32Float
        pigmentPipeline = try device.makeRenderPipelineState(descriptor: pigmentDescriptor)

        let outputDescriptor = MTLRenderPipelineDescriptor()
        outputDescriptor.vertexFunction = vertex
        outputDescriptor.fragmentFunction = output
        outputDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
        outputPipeline = try device.makeRenderPipelineState(descriptor: outputDescriptor)
        blueNoiseTexture = try Self.makeBlueNoiseTexture(device: device, bundle: bundle)
        uniforms = Self.makeComposition()
        super.init()
        Self.logger.notice("renderer initialized successfully build=\(build, privacy: .public)")
    }

    func attach(to view: MTKView) {
        mtkView(view, drawableSizeWillChange: view.drawableSize)
    }

    func startNewComposition() {
        uniforms = Self.makeComposition()
        startedAt = ProcessInfo.processInfo.systemUptime
        Self.logger.notice("new composition scenario=\(Int(self.uniforms.surface.z)) durationSeconds=\(abs(self.uniforms.surface.w)) curve=\(Int(self.uniforms.motion.x))")
    }

    func shutdown() {
        // A committed command buffer retains every texture it references until
        // the GPU finishes. Drain the final frame before dropping our texture
        // so teardown has deterministic ownership rather than eventual release.
        lastCommandBuffer?.waitUntilCompleted()
        lastCommandBuffer = nil
        pigmentTexture = nil
        drawableSize = MTLSize(width: 0, height: 0, depth: 1)
        Self.logger.notice("renderer shutdown submittedFrames=\(self.submittedFrameCount)")
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let requestedWidth = max(1, Int(size.width))
        let requestedHeight = max(1, Int(size.height))
        let longestSide = max(requestedWidth, requestedHeight)
        let scale = min(1, Double(Self.maximumPigmentDimension) / Double(longestSide))
        let width = max(1, Int(floor(Double(requestedWidth) * scale)))
        let height = max(1, Int(floor(Double(requestedHeight) * scale)))
        guard width != drawableSize.width || height != drawableSize.height else { return }
        drawableSize = MTLSize(width: width, height: height, depth: 1)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        pigmentTexture = device.makeTexture(descriptor: descriptor)
        if pigmentTexture == nil {
            Self.logger.error("failed to allocate pigment texture requested=\(requestedWidth)x\(requestedHeight) capped=\(width)x\(height)")
        } else {
            reportedMissingPigmentTexture = false
            Self.logger.notice("drawable resized requested=\(requestedWidth)x\(requestedHeight) pigment=\(width)x\(height)")
        }
    }

    func draw(in view: MTKView) {
        guard let pigmentTexture else {
            if !reportedMissingPigmentTexture {
                reportedMissingPigmentTexture = true
                Self.logger.error("draw skipped: pigment texture unavailable viewDrawable=\(Int(view.drawableSize.width))x\(Int(view.drawableSize.height))")
            }
            return
        }
        guard let renderPass = view.currentRenderPassDescriptor else {
            if !reportedMissingRenderPass {
                reportedMissingRenderPass = true
                Self.logger.error("draw skipped: currentRenderPassDescriptor unavailable windowAttached=\(view.window != nil)")
            }
            return
        }
        guard let drawable = view.currentDrawable else {
            if !reportedMissingDrawable {
                reportedMissingDrawable = true
                Self.logger.error("draw skipped: currentDrawable unavailable windowAttached=\(view.window != nil) hidden=\(view.isHiddenOrHasHiddenAncestor)")
            }
            return
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            if !reportedMissingCommandBuffer {
                reportedMissingCommandBuffer = true
                Self.logger.error("draw skipped: command buffer unavailable")
            }
            return
        }
        reportedMissingRenderPass = false
        reportedMissingDrawable = false
        reportedMissingCommandBuffer = false

        let elapsed = Float(ProcessInfo.processInfo.systemUptime - startedAt)
        uniforms.resolutionAndTime = SIMD4(Float(drawableSize.width), Float(drawableSize.height), elapsed, 0)

        let pigmentPass = MTLRenderPassDescriptor()
        pigmentPass.colorAttachments[0].texture = pigmentTexture
        pigmentPass.colorAttachments[0].loadAction = .dontCare
        pigmentPass.colorAttachments[0].storeAction = .store
        guard let pigmentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: pigmentPass) else {
            Self.logger.error("could not create pigment render encoder")
            return
        }
        pigmentEncoder.setRenderPipelineState(pigmentPipeline)
        pigmentEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<ZibreiroUniforms>.stride, index: 0)
        pigmentEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        pigmentEncoder.endEncoding()

        guard let outputEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            Self.logger.error("could not create output render encoder")
            return
        }
        outputEncoder.setRenderPipelineState(outputPipeline)
        // Algorithm 007 uses time to advance its centre-panel temporal
        // dither. Earlier output shaders simply leave this buffer unused.
        outputEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<ZibreiroUniforms>.stride, index: 0)
        outputEncoder.setFragmentTexture(pigmentTexture, index: 0)
        outputEncoder.setFragmentTexture(blueNoiseTexture, index: 1)
        outputEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        outputEncoder.endEncoding()
        commandBuffer.label = "Zibreiro frame \(submittedFrameCount + 1)"
        commandBuffer.addCompletedHandler { [weak self] completedBuffer in
            self?.recordCompletion(completedBuffer, drawable: drawable)
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        submittedFrameCount += 1
        if submittedFrameCount == 1 {
            Self.logger.notice("first frame submitted drawable=\(Int(view.drawableSize.width))x\(Int(view.drawableSize.height)) pigment=\(self.drawableSize.width)x\(self.drawableSize.height) windowAttached=\(view.window != nil)")
        }
        lastCommandBuffer = commandBuffer
    }

    private func recordCompletion(_ commandBuffer: MTLCommandBuffer, drawable: CAMetalDrawable) {
        if commandBuffer.status == .error {
            Self.logger.error("Metal command buffer failed status=\(commandBuffer.status.rawValue) error=\(commandBuffer.error?.localizedDescription ?? "unknown", privacy: .public)")
            return
        }
        completionLock.lock()
        defer { completionLock.unlock() }
        guard !reportedFirstCompletion else { return }
        reportedFirstCompletion = true
        Self.logger.notice("first frame completed status=\(commandBuffer.status.rawValue) presentedTime=\(drawable.presentedTime)")
    }

    private static func makeComposition() -> ZibreiroUniforms {
        func random(_ lower: Float, _ upper: Float) -> Float { Float.random(in: lower...upper) }
        func color(_ base: SIMD3<Float>) -> SIMD4<Float> {
            SIMD4(max(0.005, min(0.95, base.x + random(-0.035, 0.035))),
                  max(0.005, min(0.95, base.y + random(-0.035, 0.035))),
                  max(0.005, min(0.95, base.z + random(-0.035, 0.035))), 1)
        }
        let paletteFamilies: [[SIMD3<Float>]] = [
            // Restrained umbers, reds, and ochres.
            [SIMD3(0.055, 0.026, 0.020), SIMD3(0.42, 0.055, 0.028), SIMD3(0.76, 0.22, 0.065), SIMD3(0.86, 0.54, 0.17), SIMD3(0.12, 0.045, 0.085), SIMD3(0.62, 0.40, 0.18)],
            // Deep green (the legacy first composition family).
            [SIMD3(0.008, 0.025, 0.018), SIMD3(0.025, 0.16, 0.08), SIMD3(0.08, 0.40, 0.18), SIMD3(0.34, 0.48, 0.18), SIMD3(0.02, 0.08, 0.065), SIMD3(0.24, 0.38, 0.18)],
            // Bruised magenta, red, and gold.
            [SIMD3(0.045, 0.018, 0.035), SIMD3(0.34, 0.06, 0.12), SIMD3(0.70, 0.18, 0.24), SIMD3(0.78, 0.46, 0.20), SIMD3(0.08, 0.035, 0.10), SIMD3(0.55, 0.28, 0.25)],
            // Vermilion above deep ultramarine, after the horizon references.
            [SIMD3(0.018, 0.022, 0.070), SIMD3(0.30, 0.035, 0.025), SIMD3(0.88, 0.15, 0.045), SIMD3(0.94, 0.39, 0.055), SIMD3(0.025, 0.055, 0.20), SIMD3(0.07, 0.18, 0.48)],
            // Cobalt, plum, and muted rose for the cooler stacked fields.
            [SIMD3(0.010, 0.018, 0.065), SIMD3(0.05, 0.12, 0.42), SIMD3(0.16, 0.28, 0.70), SIMD3(0.34, 0.40, 0.72), SIMD3(0.16, 0.035, 0.16), SIMD3(0.38, 0.15, 0.30)]
        ]
        let palette = paletteFamilies[Int.random(in: 0..<paletteFamilies.count)]
        var value = ZibreiroUniforms()
        value.placement = SIMD4(random(0, 1000), random(0.68, 0.78), random(0.44, 0.56), random(0.20, 0.32))
        value.widthsAndTopHeight = SIMD4(random(0.35, 0.48), random(0.38, 0.50), random(0.36, 0.49), random(0.12, 0.19))
        value.heightsAndMaterial = SIMD4(random(0.10, 0.17), random(0.12, 0.19), random(0.075, 0.145), random(0.25, 1.0))
        // All named compositions share the same palette generation and output pass.
        // The first four compositions get a fresh 10–200 minute vertical
        // sweep; the circle instead gets a 5–30 minute, slow heartbeat cycle.
        let scenario = Scenario.allCases.randomElement()!
        let duration: Float
        if scenario == .smokyCircle {
            value.placement = SIMD4(random(0, 1000), random(0.38, 0.62), random(0.40, 0.60), random(0, 1))
            duration = random(5 * 60, 30 * 60)
        } else {
            duration = random(10 * 60, 200 * 60) * (Bool.random() ? 1 : -1)
        }
        value.surface = SIMD4(random(0.15, 1.0), random(0.55, 1.0), scenario.shaderValue, duration)
        // Each non-circle composition chooses an easing curve for its shared
        // vertical sweep: smoothstep, sine, cubic, or quartic.
        value.motion.x = Float(Int.random(in: 0...3))
        let colors = palette.map(color)
        value.baseDark = colors[0]
        value.deepRed = colors[1]
        value.ember = colors[2]
        value.ochre = colors[3]
        value.bruised = colors[4]
        value.smokeGold = colors[5]
        if scenario == .smokyCircle {
            let primaryChoices = [1, 2, 3, 5]
            let primaryIndex = primaryChoices.randomElement()!
            let accentIndex = primaryChoices.filter { $0 != primaryIndex }.randomElement()!
            // The circle uses one clearly dominant pigment and one independently
            // selected accent, while the remaining palette supplies its dark field.
            value.ember = colors[primaryIndex]
            value.smokeGold = colors[accentIndex]
        }
        return value
    }

    private static func makeBlueNoiseTexture(device: MTLDevice, bundle: Bundle) throws -> MTLTexture {
        let side = 128
        guard let url = bundle.url(forResource: "blue-noise-128", withExtension: "raw") else {
            throw RendererError.blueNoiseMissing
        }
        let data = try Data(contentsOf: url)
        guard data.count == side * side else {
            throw RendererError.blueNoiseInvalid
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: side, height: side, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.blueNoiseInvalid
        }
        data.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, side, side),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: side)
        }
        return texture
    }

    private enum RendererError: LocalizedError {
        case metalLibraryMissing
        case metalSetupFailed
        case blueNoiseMissing
        case blueNoiseInvalid

        var errorDescription: String? {
            switch self {
            case .metalLibraryMissing: return "default.metallib is missing from the screen saver bundle"
            case .metalSetupFailed: return "Metal queue or shader functions could not be created"
            case .blueNoiseMissing: return "blue-noise-128.raw is missing from the screen saver bundle"
            case .blueNoiseInvalid: return "The blue-noise texture could not be created"
            }
        }
    }
}
