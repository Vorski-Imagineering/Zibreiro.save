# Zibreiro Algorithm Modules

Each numbered `.metalinc` file is an immutable rendering-algorithm checkpoint. `ZibreiroShaders.metal` selects one module with `ZIBREIRO_ALGORITHM_VERSION`.

Build a specific version with:

```sh
ZIBREIRO_ALGORITHM_VERSION=1 ./build.sh
```

## Versions

- **001 — WebGL sRGB dither:** Direct WebGL color port, 32-bit float pigment texture, 16-bit float sRGB-tagged drawable, and stable one-code-value output dither. Preserved from bundle version 13. The 4K reference capture showed that its dark central field occupies only about 30 captured luminance levels; the squared pigment colors and strong vignette are the likely remaining banding pressure points.
- **002 — Shadow range:** Replaces squared-palette mixing with mix-first pigment density using a 1.35 exponent. This preserves the dark painted character while allocating more output levels to shadow gradients. Geometry, animation, textures, precision, and dithering are unchanged for a controlled comparison.
- **003 — Six-bit display dither (rejected):** Kept algorithm 002's color math and increased the procedural monochrome dither from one to four codes peak-to-peak. It visibly increased banding on the cheaper monitor, indicating that the correlated interleaved-gradient pattern interacted poorly with the display/FRC. Preserved as a failed experiment; algorithm 002 remains the default.
- **004 — Blue-noise texture:** Kept algorithm 002's color math, restored one-code peak-to-peak amplitude, and replaced the correlated procedural hash with a deterministic 128x128 isotropic blue-noise texture. It did not materially improve the cheap monitor. The checked-in raw tile is reproducible with `Tools/generate_blue_noise.py`.
- **005 — Four-code blue noise:** Keeps algorithm 004's texture and color math, increasing only blue-noise amplitude to four output codes peak-to-peak. This tests enough uncorrelated amplitude to bridge a nominal 6-bit panel step without the structured procedural pattern that made algorithm 003 worse.
- **006 — Protected black:** Keeps algorithm 005's color and blue-noise path, adds a hue-preserving six-code black point, and fades dithering out over the first sixteen luminance codes. This guarantees that exact black remains `0,0,0` rather than being lifted by positive dither samples.
- **007 — Side-by-side shadow diagnostics (rejected):** Repeats the pigment field in three columns: algorithm 006's static output, temporally shifted blue noise, and an expanded shadow toe. The GPU output pass renders the intended triptych off-screen, but the deployed experiment produced unusable horizontal structure and was not a valid controlled comparison: it retained random selection among four substantially different composition scenarios, including deliberately horizontal strata. Algorithm 006 remains the default.

Never overwrite a numbered module after testing it. Copy it to the next number and update the selector instead.
## Composition scenarios

Within algorithm 006, compositions are randomly selected whenever the screen saver starts:

- Scenario 1: the original three-form composition.
- Scenario 2: two broad, independently coloured bands that drift and breathe on hour-scale cycles.
- Scenario 3: a warm/cool horizon field with a painted boundary.
- Scenario 4: four quiet horizontal strata with irregular edges.
