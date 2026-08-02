import AppKit
import Foundation
import ScreenSaver

guard CommandLine.arguments.count == 2 else {
    fputs("usage: host-screen-saver /path/to/Zibreiro.saver\n", stderr)
    exit(2)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let bundlePath = CommandLine.arguments[1]
guard let bundle = Bundle(path: bundlePath), bundle.load(),
      let saverType = bundle.principalClass as? ScreenSaverView.Type,
      let screen = NSScreen.main else {
    fputs("could not load screen saver bundle or main screen\n", stderr)
    exit(1)
}

let window = NSWindow(
    contentRect: screen.frame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false,
    screen: screen)
window.level = .screenSaver
window.backgroundColor = .black
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

guard let saver = saverType.init(frame: NSRect(origin: .zero, size: screen.frame.size), isPreview: false) else {
    fputs("screen saver principal class rejected initialization\n", stderr)
    exit(1)
}
window.contentView = saver
window.makeKeyAndOrderFront(nil)
window.orderFrontRegardless()
app.activate(ignoringOtherApps: true)
saver.startAnimation()
print("HOST_STARTED frame=\(Int(screen.frame.width))x\(Int(screen.frame.height))")
fflush(stdout)

Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { _ in
    saver.stopAnimation()
    window.orderOut(nil)
    app.terminate(nil)
}

app.run()
