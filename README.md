# Zibreiro macOS Screen Saver

A meditative colour wash saver, inspired by a great artist.

Looking forward to pull requests with suggested improvements.

## Make it your own with Claude or Codex

You do not need to be an experienced programmer to experiment with Zibreiro. Pull the repository, open a terminal in its folder, and start Claude Code or Codex:

```sh
git clone https://github.com/Vorski-Imagineering/Zibreiro.save.git
cd Zibreiro.save
claude
# Or use Codex:
codex
```

Then describe the change you want in plain language. For example:

- “Make the colour transitions slower and more subtle.”
- “Add a new palette based on deep blues and warm golds.”
- “Reduce the grain and make the edges between colours softer.”
- “Add a setting that controls the animation speed.”
- “Build the screen saver, fix any errors, and explain how I can install it.”

Ask Claude or Codex to build and test its changes before you try them. Review the changes it makes, and consider opening a pull request if your improvement may be useful to others.

## Toolchain and compatibility

Environment inspected on 2026-08-01:

- macOS 15.5 (24F74)
- Swift 6.1.2 (`swiftlang-6.1.2.1.2`, arm64)
- macOS SDK 15.5 at `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`
- `ScreenSaver.framework` is present in the SDK, with headers, module map, and link stub
- The checked-in Metal shader needs full Xcode; Apple Command Line Tools do not provide `metal` or `metallib`

Full Xcode must be installed from Apple's Mac App Store; the standalone Apple Command Line Tools are not enough. Open Xcode once after installing it, accept any requested components, and select it for command-line builds if necessary:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

The checked-in Xcode project is ready for full Xcode, and `build.sh` builds directly once Xcode is selected. The bundle links against `ScreenSaver.framework`, `Metal.framework`, and `MetalKit.framework`.

## Build

From the repository root:

```sh
./build.sh
```

The output is `build/Zibreiro.saver`. The script compiles the native code and Metal library, copies the bundle Info.plist, preserves the legacy HTML reference resource, validates the plist, and applies an ad-hoc local signature.

To override the deployment target when appropriate:

```sh
MACOSX_DEPLOYMENT_TARGET=15.0 ./build.sh
```

## Install locally

Install for the current user:

```sh
mkdir -p "$HOME/Library/Screen Savers"
ditto build/Zibreiro.saver "$HOME/Library/Screen Savers/Zibreiro.saver"
```

If an older copy is already installed, remove that specific bundle before copying the new build:

```sh
rm -rf "$HOME/Library/Screen Savers/Zibreiro.saver"
ditto build/Zibreiro.saver "$HOME/Library/Screen Savers/Zibreiro.saver"
```

## Test locally

1. Open **System Settings → Wallpaper → Screen Saver**.
2. Select **Zibreiro** in the screen saver list. The preview should show the animated colour washes.
3. Use **Preview** or enable the screen saver and wait for it to start. Confirm that the pigment fields continue animating without a blank view.
4. To inspect the installed bundle and resource:

```sh
plutil -p "$HOME/Library/Screen Savers/Zibreiro.saver/Contents/Info.plist"
file "$HOME/Library/Screen Savers/Zibreiro.saver/Contents/MacOS/Zibreiro"
open "$HOME/Library/Screen Savers/Zibreiro.saver/Contents/Resources/index.html"
```

The last command opens the preserved legacy WebGL source in the default browser. The actual screen saver test must use the Screen Saver preview or full-screen mode, which exercises the native Metal renderer.

## Xcode project

Open `ZibreiroScreenSaver.xcodeproj` in full Xcode when available and choose the `Zibreiro` target. Its product type is a bundle with `.saver` extension, and its resources and Info.plist are configured to match the command-line build.

The Metal visualizer selects one of three palette families—umber/red, green, or bruised-magenta—then randomizes its band placement, proportions, edge softness, drift, grain, vignette, and individual color channels on every `startAnimation()` invocation, including reused Preview views. It has no external dependencies. `Resources/index.html` remains intentionally preserved as the legacy WebGL implementation, but it is not loaded by the saver.

The saver creates its Metal view and renderer only while animation is active. `stopAnimation()` removes the Metal view and releases the renderer so inactive previews do not retain high-resolution drawable pools or pigment textures in the system screen-saver host.

## Algorithm versions

Rendering experiments are preserved as immutable numbered modules under `Shaders/Algorithms`. Build an earlier checkpoint by setting `ZIBREIRO_ALGORITHM_VERSION`; for example:

```sh
ZIBREIRO_ALGORITHM_VERSION=1 ./build.sh
```

The selected version is written to `ZibreiroAlgorithmVersion` in the built bundle's Info.plist. See `Shaders/Algorithms/README.md` for version notes and comparison findings.

## Bugs and Quandries

The main open visual problem is pronounced banding in the darkest, smoothest pigment fields. On the physical displays it can present as vertical strips rather than only as the broad contour bands normally associated with 8-bit gradients. This is most noticeable in deep greens and near-black fields, and it can vary by display.

### What we have tried

- Moved from the legacy WebGL/WKWebView renderer to native Metal, driven directly by the Screen Saver timer.
- Confirmed rendering uses the display's native backing resolution rather than logical point resolution.
- Kept the pigment calculation in a 32-bit floating-point texture and the drawable in sRGB-tagged 16-bit floating point, so the shader itself is not quantizing each intermediate operation to 8 bits.
- Added painterly grain and output-code-space dithering to decorrelate the final display quantization.
- Replaced an early large-coordinate hash dither, which could itself form structured stripes, with precision-safe interleaved-gradient noise and then texture-backed blue noise.
- Compared several algorithm versions: widening shadow range, increasing dither amplitude, changing pigment mixing, and protecting exact black. The four-code procedural dither was rejected because it made bands more obvious on one display, likely through interaction with panel temporal dithering/FRC.

### What we suspect

The remaining banding is probably not a single bug. The strongest candidates are:

- The shader's very compressed dark range: squared pigment colors and strong vignetting can leave only a small number of distinguishable display luminance levels in the darkest fields.
- The final conversion from the float render path to the physical display's 8- or 10-bit panel output.
- Display-specific FRC, temporal dithering, colour management, or cable/monitor processing interacting with our stable dither pattern.
- A residual interaction between the dither pattern, the display pixel grid, and the deliberately broad vertical colour gradients.

We do not yet know how much is intrinsic to a given monitor versus the screen saver, Metal drawable configuration, or shader. The algorithm captures and notes under `Shaders/Algorithms/` are intended to keep each experiment comparable rather than treating a subjective improvement on one display as a universal fix.

Ideas, references, test captures, and alternative hypotheses are very welcome. Useful contributions would include a reproducible test, a different dither strategy, an output-transform proposal, or an explanation of why a particular panel/FRC path would create vertical strips. Please add new experiments as a numbered shader algorithm so the current baseline remains reproducible.
