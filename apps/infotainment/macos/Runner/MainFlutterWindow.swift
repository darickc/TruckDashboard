import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Development window matching the target panel (original Raspberry Pi
    // 7" touchscreen, 800x480). Resizing is allowed; the app letterboxes
    // and scales the 800x480 layout (PreviewFrame), so the layout itself
    // never changes.
    let panel = NSSize(width: 800, height: 480)
    self.setContentSize(panel)
    self.contentMinSize = NSSize(width: 400, height: 240)
    self.contentAspectRatio = panel
    self.title = "F-250 head unit (simulated)"
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
