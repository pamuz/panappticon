import AppKit
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var isRecording = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard initializeDatabase() else {
            NSApplication.shared.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        buildMenu()
    }

    private func initializeDatabase() -> Bool {
        let password: String

        if let stored = KeychainManager.shared.getPassword() {
            password = stored
        } else {
            let result = PasswordPrompt.promptForNewPassword()
            switch result {
            case .password(let newPassword):
                if !KeychainManager.shared.setPassword(newPassword) {
                    print("Failed to save password to Keychain")
                    return false
                }
                password = newPassword
            case .cancelled:
                return false
            }
        }

        DatabaseManager.shared.initialize(password: password)
        return true
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
            MediaMonitor.shared.stop()
            ScreenshotMonitor.shared.stop()
            isRecording = false
        } else {
            if !checkAccessibilityPermissions() {
                return
            }
            KeystrokeMonitor.shared.start()
            MediaMonitor.shared.start()
            ScreenshotMonitor.shared.start()
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
            MediaMonitor.shared.stop()
            ScreenshotMonitor.shared.stop()
        }
        DatabaseManager.shared.close()
        NSApplication.shared.terminate(nil)
    }
}
