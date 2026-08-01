# Rothko macOS Screen Saver

Minimal Phase 0 checkpoint for a native macOS `.saver` bundle. The current implementation contains a `ScreenSaverView` subclass, a local animated-gradient HTML page, and a `WKWebView` that loads that page from the bundle.

## Toolchain and compatibility

Environment inspected on 2026-08-01:

- macOS 15.5 (24F74)
- Swift 6.1.2 (`swiftlang-6.1.2.1.2`, arm64)
- macOS SDK 15.5 at `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`
- `ScreenSaver.framework` is present in the SDK, with headers, module map, and link stub
- `WebKit.framework` is present in the SDK, with headers, module map, and link stub

Full Xcode is not installed on this machine. `xcode-select` points to `/Library/Developer/CommandLineTools`, so `xcodebuild` cannot run. The checked-in Xcode project is ready for full Xcode, while `build.sh` provides the equivalent local build using the installed Apple Command Line Tools. No framework workaround is used: the bundle links against the SDK's genuine `ScreenSaver.framework` and `WebKit.framework`.

## Build

From the repository root:

```sh
./build.sh
```

The output is `build/Rothko.saver`. The script compiles an arm64 bundle for macOS 15.0 or later, copies the bundle Info.plist and local HTML resource, validates the plist, and applies an ad-hoc local signature.

To override the deployment target when appropriate:

```sh
MACOSX_DEPLOYMENT_TARGET=15.0 ./build.sh
```

## Install locally

Install for the current user:

```sh
mkdir -p "$HOME/Library/Screen Savers"
ditto build/Rothko.saver "$HOME/Library/Screen Savers/Rothko.saver"
```

If an older copy is already installed, remove that specific bundle before copying the new build:

```sh
rm -rf "$HOME/Library/Screen Savers/Rothko.saver"
ditto build/Rothko.saver "$HOME/Library/Screen Savers/Rothko.saver"
```

## Test locally

1. Open **System Settings → Wallpaper → Screen Saver**.
2. Select **Rothko** in the screen saver list. The preview should show the animated gradient.
3. Use **Preview** or enable the screen saver and wait for it to start. Confirm that the gradient continues animating without a blank view.
4. To inspect the installed bundle and resource:

```sh
plutil -p "$HOME/Library/Screen Savers/Rothko.saver/Contents/Info.plist"
file "$HOME/Library/Screen Savers/Rothko.saver/Contents/MacOS/Rothko"
open "$HOME/Library/Screen Savers/Rothko.saver/Contents/Resources/index.html"
```

The last command opens the source HTML in the default browser; the actual screen saver test must use the Screen Saver preview or full-screen mode so that the `ScreenSaverView` host and bundled `WKWebView` are exercised.

## Xcode project

Open `RothkoScreenSaver.xcodeproj` in full Xcode when available and choose the `Rothko` target. Its product type is a bundle with `.saver` extension, and its resources and Info.plist are configured to match the command-line build.

This Phase 0 intentionally excludes the Rothko/WebGL visualizer, audio, configuration controls, and additional architecture.
