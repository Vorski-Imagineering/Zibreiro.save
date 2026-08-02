import Foundation
import Metal
import simd

struct ZibreiroUniforms {
    var resolutionAndTime = SIMD4<Float>(repeating: 0)
    var placement = SIMD4<Float>(repeating: 0)
    var widthsAndTopHeight = SIMD4<Float>(repeating: 0)
    var heightsAndMaterial = SIMD4<Float>(repeating: 0)
    var surface = SIMD4<Float>(repeating: 0)
    var motion = SIMD4<Float>(repeating: 0)
    var baseDark = SIMD4<Float>(repeating: 0)
    var deepRed = SIMD4<Float>(repeating: 0)
    var ember = SIMD4<Float>(repeating: 0)
    var ochre = SIMD4<Float>(repeating: 0)
    var bruised = SIMD4<Float>(repeating: 0)
    var smokeGold = SIMD4<Float>(repeating: 0)
}

enum ValidationError: Error, CustomStringConvertible {
    case usage
    case setup(String)
    case command(String)
    case blackOutput(Float)

    var description: String {
        switch self {
        case .usage: return "usage: validate-renderer /path/to/Zibreiro.saver"
        case .setup(let message): return "setup failed: \(message)"
        case .command(let message): return "Metal command failed: \(message)"
        case .blackOutput(let maximum): return "rendered output is black (maximum sampled luminance \(maximum))"
        }
    }
}

func makeTexture(
    device: MTLDevice,
    pixelFormat: MTLPixelFormat,
    width: Int,
    height: Int,
    usage: MTLTextureUsage,
    storageMode: MTLStorageMode
) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
    descriptor.usage = usage
    descriptor.storageMode = storageMode
    guard let texture = device.makeTexture(descriptor: descriptor) else {
        throw ValidationError.setup("could not allocate \(pixelFormat) texture \(width)x\(height)")
    }
    return texture
}

func validate(bundlePath: String) throws {
    guard MemoryLayout<ZibreiroUniforms>.stride == 192 else {
        throw ValidationError.setup("uniform stride is \(MemoryLayout<ZibreiroUniforms>.stride), expected 192")
    }
    guard let bundle = Bundle(path: bundlePath),
          let libraryURL = bundle.url(forResource: "default", withExtension: "metallib"),
          let noiseURL = bundle.url(forResource: "blue-noise-128", withExtension: "raw"),
          let device = MTLCreateSystemDefaultDevice() else {
        throw ValidationError.setup("bundle resources or default Metal device unavailable")
    }
    let library = try device.makeLibrary(URL: libraryURL)
    guard let vertex = library.makeFunction(name: "fullscreenVertex"),
          let pigment = library.makeFunction(name: "pigmentFragment"),
          let output = library.makeFunction(name: "outputFragment"),
          let queue = device.makeCommandQueue(),
          let commandBuffer = queue.makeCommandBuffer() else {
        throw ValidationError.setup("shader functions or command queue unavailable")
    }

    let pigmentPipelineDescriptor = MTLRenderPipelineDescriptor()
    pigmentPipelineDescriptor.vertexFunction = vertex
    pigmentPipelineDescriptor.fragmentFunction = pigment
    pigmentPipelineDescriptor.colorAttachments[0].pixelFormat = .rgba32Float
    let pigmentPipeline = try device.makeRenderPipelineState(descriptor: pigmentPipelineDescriptor)

    let outputPipelineDescriptor = MTLRenderPipelineDescriptor()
    outputPipelineDescriptor.vertexFunction = vertex
    outputPipelineDescriptor.fragmentFunction = output
    outputPipelineDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
    let outputPipeline = try device.makeRenderPipelineState(descriptor: outputPipelineDescriptor)

    let pigmentWidth = 2560
    let pigmentHeight = 1440
    let outputWidth = 5120
    let outputHeight = 2880
    let pigmentTexture = try makeTexture(
        device: device, pixelFormat: .rgba32Float,
        width: pigmentWidth, height: pigmentHeight,
        usage: [.renderTarget, .shaderRead], storageMode: .private)
    let outputTexture = try makeTexture(
        device: device, pixelFormat: .rgba16Float,
        width: outputWidth, height: outputHeight,
        usage: [.renderTarget, .shaderRead], storageMode: .shared)
    let noiseTexture = try makeTexture(
        device: device, pixelFormat: .r8Unorm,
        width: 128, height: 128, usage: .shaderRead, storageMode: .shared)
    let noise = try Data(contentsOf: noiseURL)
    guard noise.count == 128 * 128 else {
        throw ValidationError.setup("blue-noise resource has \(noise.count) bytes")
    }
    noise.withUnsafeBytes { bytes in
        noiseTexture.replace(
            region: MTLRegionMake2D(0, 0, 128, 128), mipmapLevel: 0,
            withBytes: bytes.baseAddress!, bytesPerRow: 128)
    }

    var uniforms = ZibreiroUniforms()
    uniforms.resolutionAndTime = SIMD4(Float(pigmentWidth), Float(pigmentHeight), 60, 0)
    uniforms.placement = SIMD4(127, 0.72, 0.50, 0.26)
    uniforms.widthsAndTopHeight = SIMD4(0.42, 0.44, 0.42, 0.16)
    uniforms.heightsAndMaterial = SIMD4(0.14, 0.16, 0.10, 0.55)
    uniforms.surface = SIMD4(0.55, 0.72, 0, 3600)
    uniforms.motion = SIMD4(1, 0, 0, 0)
    uniforms.baseDark = SIMD4(0.055, 0.026, 0.020, 1)
    uniforms.deepRed = SIMD4(0.42, 0.055, 0.028, 1)
    uniforms.ember = SIMD4(0.76, 0.22, 0.065, 1)
    uniforms.ochre = SIMD4(0.86, 0.54, 0.17, 1)
    uniforms.bruised = SIMD4(0.12, 0.045, 0.085, 1)
    uniforms.smokeGold = SIMD4(0.62, 0.40, 0.18, 1)

    let pigmentPass = MTLRenderPassDescriptor()
    pigmentPass.colorAttachments[0].texture = pigmentTexture
    pigmentPass.colorAttachments[0].loadAction = .clear
    pigmentPass.colorAttachments[0].storeAction = .store
    pigmentPass.colorAttachments[0].clearColor = MTLClearColorMake(1, 0, 1, 1)
    guard let pigmentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: pigmentPass) else {
        throw ValidationError.setup("pigment encoder unavailable")
    }
    pigmentEncoder.setRenderPipelineState(pigmentPipeline)
    pigmentEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<ZibreiroUniforms>.stride, index: 0)
    pigmentEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    pigmentEncoder.endEncoding()

    let outputPass = MTLRenderPassDescriptor()
    outputPass.colorAttachments[0].texture = outputTexture
    outputPass.colorAttachments[0].loadAction = .clear
    outputPass.colorAttachments[0].storeAction = .store
    outputPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 1, 1, 1)
    guard let outputEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: outputPass) else {
        throw ValidationError.setup("output encoder unavailable")
    }
    outputEncoder.setRenderPipelineState(outputPipeline)
    outputEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<ZibreiroUniforms>.stride, index: 0)
    outputEncoder.setFragmentTexture(pigmentTexture, index: 0)
    outputEncoder.setFragmentTexture(noiseTexture, index: 1)
    outputEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    outputEncoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    guard commandBuffer.status == .completed else {
        throw ValidationError.command(commandBuffer.error?.localizedDescription ?? "status \(commandBuffer.status.rawValue)")
    }

    var maximumLuminance: Float = 0
    var totalLuminance: Float = 0
    var sampleCount: Float = 0
    for yFraction in 1...9 {
        for xFraction in 1...9 {
            let x = outputWidth * xFraction / 10
            let y = outputHeight * yFraction / 10
            var components = [UInt16](repeating: 0, count: 4)
            outputTexture.getBytes(
                &components, bytesPerRow: 8,
                from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
            let red = Float(Float16(bitPattern: components[0]))
            let green = Float(Float16(bitPattern: components[1]))
            let blue = Float(Float16(bitPattern: components[2]))
            let luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722
            maximumLuminance = max(maximumLuminance, luminance)
            totalLuminance += luminance
            sampleCount += 1
        }
    }
    let meanLuminance = totalLuminance / sampleCount
    guard maximumLuminance > 0.03 else {
        throw ValidationError.blackOutput(maximumLuminance)
    }
    print("PASS device=\(device.name) pigment=\(pigmentWidth)x\(pigmentHeight) output=\(outputWidth)x\(outputHeight) meanLuminance=\(meanLuminance) maxLuminance=\(maximumLuminance)")
}

do {
    guard CommandLine.arguments.count == 2 else { throw ValidationError.usage }
    try validate(bundlePath: CommandLine.arguments[1])
} catch {
    fputs("FAIL \(error)\n", stderr)
    exit(1)
}
