# Zibreiro development notes

These instructions apply to the entire repository. Preserve them when changing the screen-saver lifecycle or Metal renderer.

## The macOS lifecycle bug is real

On macOS Sonoma and Sequoia, `WallpaperAgent` can ask `legacyScreenSaver.appex` to create a new `ScreenSaverView` on every run without reliably calling `stopAnimation()` or destroying the old views. The retained views continue receiving `animateOneFrame()` and keep their Metal resources alive.

This was observed locally on macOS 15.5 as six retained windows across two displays. The host footprint reached about 3.5 GB: approximately 2.2 GB of `IOSurface` memory and 1.15 GB of `IOAccelerator (graphics)` memory. This is the same Sonoma+ stacking bug documented by AerialScreensaver's `ScreenSaverMinimal` project. Do not treat a lingering `legacyScreenSaver (Wallpaper)` process as harmless without measuring its footprint and checking whether it is still drawing.

## Required lifecycle design

- Keep the `com.apple.screensaver.willstop` and `com.apple.screensaver.didstop` observers for full-screen, non-preview instances.
- On either stop notification, immediately release the renderer, prevent it from being recreated, and terminate the dedicated legacy host after the two-second exit transition. This process-exit workaround is intentionally heavy-handed: it is the hard guarantee that retained host views, drawable pools, and GPU heaps cannot accumulate across runs. It follows the workaround used by Aerial and `ScreenSaverMinimal`.
- Continue supporting the normal `stopAnimation()`, `viewDidHide()`, and window-detachment cleanup paths. They are necessary for System Settings previews even though they are insufficient for the Wallpaper host bug.
- Determine preview mode from the small preview frame (currently under 400 by 300 points), not solely from the host's `isPreview` argument. `legacyScreenSaver` has shipped releases where that argument is wrong.
- Keep MetalKit's timer disabled. `ScreenSaverView.animateOneFrame()` must remain the sole frame scheduler.
- Keep duplicate `startAnimation()` calls idempotent.

## Do not gate startup on normal NSWindow visibility

Do **not** require any of the following before creating or drawing the renderer:

- `window.isVisible`
- `window.occlusionState.contains(.visible)`
- `window.onActiveSpace`
- membership in `CGWindowListCopyWindowInfo(.optionOnScreenOnly, ...)`

The Wallpaper bridge does not expose a normal AppKit window lifecycle and can report the saver window as invisible or occluded during startup. Requiring ordinary `NSWindow` visibility caused build 26 to show only black and never start rendering. Use `ScreenSaverView` lifecycle state and view attachment/hidden state for startup. Rely on the stop-notification host exit—not occlusion—as the hard defense against retained Wallpaper instances.

## Metal memory limits and teardown

- Keep `MTKView.autoResizeDrawable` disabled and set `drawableSize` explicitly.
- Keep `CAMetalLayer.maximumDrawableCount` at two.
- Keep the longest render dimension capped at 2,560 pixels for full-screen rendering and 1,024 pixels for previews. Zibreiro's soft artwork does not benefit enough from native 5K/6K intermediate textures to justify hundreds of megabytes per view.
- Keep the renderer's offscreen pigment texture independently capped at 2,560 pixels.
- Before releasing the renderer, stop new draws, detach the `MTKView` delegate, wait for the final committed Metal command buffer, clear the offscreen texture, call `releaseDrawables()`, remove the view, and drop all strong references.
- `releaseDrawables()` alone is not a complete solution. The legacy host can retain the view/layer itself; the stop-notification process exit is what guarantees reclamation.

## Build, install, and verify

The active `xcode-select` may point to Command Line Tools, which does not contain `metal` or `metallib`. Build without changing the user's global selection:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./build.sh
```

After lifecycle changes:

1. Increment `CFBundleVersion` in `Supporting Files/Info.plist` so the installed binary is identifiable.
2. Build with full Xcode, verify the signature and plist, and install the exact built bundle into `~/Library/Screen Savers/Zibreiro.saver`.
3. Verify the installed executable hash matches the built executable.
4. Stop any previously loaded `legacyScreenSaver` process only after validating its exact PID and executable path; otherwise the old in-memory bundle will continue running.
5. Confirm the saver visibly starts. A memory fix that produces a black screen is a failed fix.
6. Exercise several start/stop cycles, including multiple displays where possible. Inspect `footprint`, not only Activity Monitor's process list.
7. Confirm the full-screen host exits shortly after `willstop` and that repeated runs do not accumulate windows or memory.

The controlled native-host regression test previously measured roughly 101 MB of renderer `IOSurface` plus graphics memory while visible and roughly 2 MB after hiding, consistently across three cycles. A simulated 5K view with ten duplicate starts remained around 300 MB total rather than growing into gigabytes. These figures are useful regression bounds, but a controlled host is not a substitute for also checking the real Wallpaper/ScreenSaver host and visible output.

## Primary references

- Apple `NSWindow.didChangeOcclusionStateNotification`: useful guidance for normal AppKit windows, but not a safe startup prerequisite in the Wallpaper bridge.
- Apple `MTKView.releaseDrawables()`: use when content stops displaying, as one part of full teardown.
- `AerialScreensaver/ScreenSaverMinimal`, especially its “About Sonoma+” notes and `handleWillStopNotification()` implementation.
- `JohnCoates/Aerial`, especially its `com.apple.screensaver.willstop` teardown and delayed host exit.
