import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard ProcessInfo.processInfo.environment["QUICK_BLUE_HIDE_TEST_WINDOW"] != "1" else {
      return
    }

    if let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }) {
      let isOnScreen = NSScreen.screens.contains { window.frame.intersects($0.visibleFrame) }
      if window.frame.width < 300 || window.frame.height < 300 || !isOnScreen {
        window.setContentSize(NSSize(width: 800, height: 600))
        window.center()
      }
      window.makeKeyAndOrderFront(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
