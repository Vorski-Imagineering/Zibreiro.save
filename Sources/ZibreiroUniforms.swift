import simd

// Every field is a float4 to make the Swift and Metal layouts unambiguous.
// Keep this declaration in lockstep with ZibreiroUniforms in ZibreiroShaders.metal.
struct ZibreiroUniforms {
    var resolutionAndTime = SIMD4<Float>(repeating: 0)
    // All except smoky-circle: seed, topY, middleY, lowerY. smoky-circle:
    // seed, centreX, centreY, spare variation.
    var placement = SIMD4<Float>(repeating: 0)
    var widthsAndTopHeight = SIMD4<Float>(repeating: 0)
    var heightsAndMaterial = SIMD4<Float>(repeating: 0) // middleH, lowerH, softness, drift
    // grain, vignette, scenario transport value, signed two-bands sweep
    // duration (or smoky-circle's 5–30 minute pulse duration).
    var surface = SIMD4<Float>(repeating: 0)
    // Non-circle vertical-sweep easing curve; remaining values reserved.
    var motion = SIMD4<Float>(repeating: 0)
    var baseDark = SIMD4<Float>(repeating: 0)
    var deepRed = SIMD4<Float>(repeating: 0)
    var ember = SIMD4<Float>(repeating: 0)
    var ochre = SIMD4<Float>(repeating: 0)
    var bruised = SIMD4<Float>(repeating: 0)
    var smokeGold = SIMD4<Float>(repeating: 0)
}
