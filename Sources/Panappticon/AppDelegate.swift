import AppKit
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var isRecording = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        buildMenu()
    }

    private func updateIcon() {
        if let button = statusItem.button {
            let symbolName = isRecording ? "keyboard.badge.ellipsis" : "keyboard"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Panappticon")
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        let toggleTitle = isRecording ? "Stop Recording" : "Start Recording"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleRecording), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleRecording() {
        if isRecording {
            KeystrokeMonitor.shared.stop()
            isRecording = false
        } else {
            if !checkAccessibilityPermissions() {
                return
            }
            KeystrokeMonitor.shared.start()
            isRecording = true
        }
        updateIcon()
        buildMenu()
    }

    private func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @objc private func quitApp() {
        if isRecording {
            KeystrokeMonitor.shared.stop()
        }
        DatabaseManager.shared.close()
        NSApplication.shared.terminate(nil)
    }
}
