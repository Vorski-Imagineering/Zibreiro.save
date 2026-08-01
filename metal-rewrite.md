# Native Metal Rewrite Specification

## Purpose

Replace the `WKWebView` and WebGL2 implementation with a native Metal renderer while preserving the current Rothko visual character, random composition system, native screen saver packaging, and reliable full-screen animation.

The rewrite should improve frame scheduling, eliminate WebKit-specific behavior, and provide a higher-precision color pipeline that reduces visible gradient banding.

## Current baseline

The existing screen saver consists of:

- A native `ScreenSaverView` subclass.
- A bundled `WKWebView` loading `Resources/index.html`.
- A WebGL2 fragment shader rendering the pigment fields.
- Native frame scheduling through `ScreenSaverView.animateOneFrame()` and `window.renderFrame(time)`.
- A 30 FPS animation interval.
- Retina rendering at `window.devicePixelRatio`, capped at 2.
- A final 8-bit WebGL canvas output with subtle output dithering.

The native frame bridge is proven to work in both the System Settings selector and full-screen Screen Saver host. Browser-owned CSS animation and `requestAnimationFrame` are not reliable in the full-screen legacy screen saver host.

## Goals

1. Preserve the visual appearance and motion of the current WebGL visualizer.
2. Render directly with Metal without WebKit, HTML, JavaScript, or browser scheduling.
3. Drive every frame from `ScreenSaverView.animateOneFrame()`.
4. Render at each display's native backing-pixel resolution.
5. Perform pigment and gradient calculations in a 16-bit floating-point intermediate texture.
6. Tone-map and dither the final image into an sRGB display drawable.
7. Support the System Settings thumbnail, full-screen Preview, idle activation, and multiple displays.
8. Keep the implementation small and screen-saver-specific.

## Non-goals

- Audio input or audio-file playback.
- Configuration controls or interactive overlays.
- User presets or persistence.
- A standalone application.
- Recreating browser APIs or retaining a WebKit fallback in the final Metal target.
- HDR output in the first Metal checkpoint.

## Prerequisite

Install full Xcode and select its developer directory. The current machine only has Apple Command Line Tools; `xcrun metal` and `xcrun metallib` are unavailable.

Verify the required tools before implementation:

```sh
xcode-select -p
xcodebuild -version
xcrun -f metal
xcrun -f metallib
xcrun --sdk macosx --show-sdk-version
```

No Metal implementation milestone is complete until the `.metal` source compiles with the installed SDK and the resulting `.saver` bundle loads locally.

## Proposed structure

```text
Sources/
  RothkoScreenSaverView.swift
  MetalRenderer.swift
  RothkoUniforms.swift
Shaders/
  RothkoShaders.metal
Supporting Files/
  Info.plist
RothkoScreenSaver.xcodeproj/
build.sh
```

`Resources/index.html` and the WebKit framework dependency should be removed only after the Metal renderer passes full-screen Preview and idle-activation testing.

## Native view integration

`RothkoScreenSaverView` will own one `MTKView` and one `MetalRenderer`.

Required behavior:

- Construct the `MTKView` with the system default `MTLDevice`.
- Size it to `ScreenSaverView.bounds` and keep it autoresized with the host view.
- Set `isPaused = true` so MetalKit does not create an independent display timer.
- Set `enableSetNeedsDisplay = false`.
- Call `metalView.draw()` from `animateOneFrame()`.
- Retain the current `animationTimeInterval` of `1.0 / 30.0` initially.
- Update the renderer when the drawable size changes.
- Render no controls, cursors, labels, or diagnostic UI.
- Fail to a native solid or gradient background if no Metal device is available.

The renderer must not rely on `Timer`, `CADisplayLink`, browser callbacks, or a second animation loop.

## Metal renderer

`MetalRenderer` will conform to `MTKViewDelegate` and own:

- `MTLDevice`
- `MTLCommandQueue`
- Render pipeline states
- Full-screen triangle vertex data or generated vertex positions
- A 16-bit floating-point intermediate texture
- A uniform buffer or per-frame uniform allocation
- Randomized composition parameters
- Animation start time

The renderer should use a full-screen triangle unless the port demonstrates a reason to retain the existing quad.

### Frame flow

```text
ScreenSaverView.animateOneFrame()
  → MTKView.draw()
  → MetalRenderer.draw(in:)
  → pigment pass into RGBA16Float texture
  → output pass with tone mapping and dithering
  → BGRA8Unorm_sRGB drawable
  → present
```

There must be at most one command buffer submitted per screen saver frame unless profiling demonstrates that separate command buffers are beneficial.

## Shader migration

Port the current GLSL ES vertex and fragment behavior to Metal Shading Language, including:

- Hash and value-noise functions.
- Six-octave FBM.
- Soft rectangle fields.
- Pigment mixing.
- Aspect-ratio correction.
- Top, middle, and lower field placement.
- Edge softness and drift.
- Fine grain and paper texture.
- Vignette.
- Middle-field breathing glow.
- Current 15% brightness adjustment.
- Palette families and randomized composition parameters.

Coordinate-system differences between WebGL and Metal must be handled explicitly. The port should compare reference frames rather than assuming identical UV orientation.

## Uniforms

Define one shared Swift/Metal uniform layout containing at least:

- Drawable resolution.
- Elapsed animation time.
- Seed.
- Top, middle, and lower field positions.
- Field widths and heights.
- Softness, drift, grain, and vignette.
- Six palette colors.

The struct must use Metal-compatible alignment. SIMD types should be preferred, and its Swift stride must be validated against the Metal declaration.

Audio uniforms may remain fixed at zero in the first native version. They should be removed entirely if the shader no longer needs them.

## Color and precision pipeline

The pigment pass must render into an offscreen texture using `rgba16Float`.

The output pass must:

1. Read the floating-point pigment result.
2. Apply any required exposure or tone mapping.
3. Convert for an sRGB display target.
4. Add spatially stable, approximately one-output-code-value monochrome dithering.
5. Clamp and write to `bgra8Unorm_srgb`.

The dithering pattern should be stable between frames to avoid shimmer. A small embedded blue-noise texture is preferred; a deterministic pixel-coordinate hash is acceptable for the first checkpoint.

The implementation should not assume that a 16-bit drawable is supported by every screen saver host. The portable baseline is a 16-bit offscreen texture followed by an 8-bit sRGB drawable.

## Random composition behavior

Port palette and geometry randomization from JavaScript to Swift.

- Generate one composition when the screen saver view starts.
- Preserve the current green-first palette behavior unless product direction changes.
- Keep parameter ranges equivalent to the WebGL implementation.
- Do not introduce interactive randomization controls.
- Avoid visible discontinuities during one screen saver session.

## Retina and multiple displays

Use `MTKView.drawableSize`; do not derive physical dimensions from logical points manually.

Acceptance requirements:

- 3840×2160 drawable on the connected 4K display when shown at 1920×1080 logical resolution.
- 5120×2880 drawable on the connected 5K display when shown at 2560×1440 logical resolution.
- Correct aspect ratio and field placement on both displays.
- Independent screen saver view instances must not share mutable per-screen state accidentally.

## Build changes

The Xcode project must:

- Link `ScreenSaver.framework`, `Metal.framework`, and `MetalKit.framework`.
- Remove `WebKit.framework` after the Metal checkpoint passes.
- Compile `RothkoShaders.metal` into the default Metal library.
- Continue producing `Rothko.saver` with `NSPrincipalClass=RothkoScreenSaverView`.
- Preserve local ad-hoc signing for development builds.

The command-line build script must compile Metal sources with `xcrun metal`, link them with `xcrun metallib`, and place the resulting library in the bundle resources. Alternatively, it may delegate to `xcodebuild` once full Xcode is installed.

## Implementation milestones

### M0 — Toolchain

- Install and select full Xcode.
- Verify `xcodebuild`, `metal`, and `metallib`.
- Confirm the existing `.saver` still builds.

### M1 — Native Metal checkpoint

- Add `MTKView` to `ScreenSaverView`.
- Render a solid color or simple animated gradient.
- Drive it exclusively from `animateOneFrame()`.
- Verify selector, full-screen Preview, and idle activation.

### M2 — Visualizer port

- Port the shader and uniform parameters.
- Match representative WebGL reference frames.
- Preserve randomized green-first composition behavior.

### M3 — Precision pipeline

- Add the `rgba16Float` intermediate texture.
- Add final tone mapping and dithering pass.
- Compare dark gradients for banding on both connected displays.

### M4 — Hardening

- Test repeated starts and stops.
- Test display changes, sleep/wake, and multiple displays.
- Profile CPU, GPU, and memory use.
- Remove WebKit and HTML implementation after successful verification.

## Acceptance criteria

The rewrite is complete when:

1. `Rothko.saver` builds with full Xcode and installs for the current user.
2. The selector thumbnail, full-screen Preview, and idle activation all animate.
3. No WebKit process, HTML, JavaScript, or browser animation loop is required.
4. The renderer uses the display's native backing resolution.
5. Pigment calculations occur in an `rgba16Float` intermediate target.
6. The final output includes stable dithering and has materially less visible banding than the WebGL baseline.
7. The visual composition remains recognizably equivalent to the current Rothko visualizer.
8. The saver remains stable across repeated starts, sleep/wake, and both connected displays.
9. No controls or interactive overlays appear.

## Estimated effort

- M0 and M1: approximately one focused day after Xcode is available.
- M2: approximately one focused day.
- M3 and visual comparison: approximately half to one day.
- M4 and multi-display hardening: approximately half to one day.

Audio support, preferences, signing for distribution, notarization, and release packaging are separate scopes.
