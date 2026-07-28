import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.title = "Verse Catch"

    RegisterGeneratedPlugins(registry: flutterViewController)
    AppDelegate.registerOcrChannel(with: flutterViewController)

    super.awakeFromNib()
  }
}
