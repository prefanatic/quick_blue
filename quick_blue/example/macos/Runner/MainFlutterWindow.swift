import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let hideTestWindow = ProcessInfo.processInfo.environment["QUICK_BLUE_HIDE_TEST_WINDOW"] == "1"
    let hiddenFrame = NSRect(x: -10000, y: -10000, width: 1, height: 1)

    if hideTestWindow {
      NSApp.setActivationPolicy(.prohibited)
      alphaValue = 0
      backgroundColor = .clear
      hasShadow = false
      isOpaque = false
      setFrame(hiddenFrame, display: false)
      orderOut(nil)
    }

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(hideTestWindow ? hiddenFrame : windowFrame, display: !hideTestWindow)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    if hideTestWindow {
      orderOut(nil)
    }
  }
}
