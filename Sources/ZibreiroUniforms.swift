import simd

// Every field is a float4 to make the Swift and Metal layouts unambiguous.
// Keep this declaration in lockstep with ZibreiroUniforms in ZibreiroShaders.metal.
struct ZibreiroUniforms {
    var resolutionAndTime = SIMD4<Float>(repeating: 0)
    var placement = SIMD4<Float>(repeating: 0) // seed, topY, middleY, lowerY
    var widthsAndTopHeight = SIMD4<Float>(repeating: 0)
    var heightsAndMaterial = SIMD4<Float>(repeating: 0) // middleH, lowerH, softness, drift
    var surface = SIMD4<Float>(repeating: 0) // grain, vignette, scenario (0...3), unused
    var baseDark = SIMD4<Float>(repeating: 0)
    var deepRed = SIMD4<Float>(repeating: 0)
    var ember = SIMD4<Float>(repeating: 0)
    var ochre = SIMD4<Float>(repeating: 0)
    var bruised = SIMD4<Float>(repeating: 0)
    var smokeGold = SIMD4<Float>(repeating: 0)
}
