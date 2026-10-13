import AppKit

// Entry point. The app is a borderless "agent" utility (floating ball + panels),
// so we drive NSApplication directly instead of using the SwiftUI App lifecycle.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
