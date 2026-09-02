import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var instanceLock: SingleInstanceLock?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let lock = SingleInstanceLock() else {
            NSApp.terminate(nil)
            return
        }
        instanceLock = lock
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard instanceLock != nil else { return }
        statusBar = StatusBarController()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
