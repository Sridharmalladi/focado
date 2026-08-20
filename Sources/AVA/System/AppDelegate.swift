import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: WindowController?
    private var hotkey: GlobalHotkey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon, no menu bar app menu — pure background app
        windowController = WindowController()
        windowController?.makeVisible()

        if Settings.shared.hotkeyEnabled {
            hotkey = GlobalHotkey(keyCode: 35, modifiers: [.command, .shift]) { [weak self] in // ⌘⇧P
                self?.toggleVisibility()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        windowController?.savePosition()
    }

    private func toggleVisibility() {
        guard let win = windowController?.window else { return }
        if win.isVisible { windowController?.makeHidden() } else { windowController?.makeVisible() }
    }
}
