import AppKit
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var isCollecting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let password = getOrCreatePassword() else {
            NSApplication.shared.terminate(nil)
            return
        }

        DatabaseManager.shared.initialize(password: password)
        DiskImageManager.shared.initialize(password: password)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        buildMenu()

        HotkeyManager.shared.start { [weak self] in
            self?.toggleCollecting()
        }
    }

    private func getOrCreatePassword() -> String? {
        if let stored = KeychainManager.shared.getPassword() {
            return stored
        }

        let result = PasswordPrompt.promptForNewPassword()
        switch result {
        case .password(let newPassword):
            if KeychainManager.shared.setPassword(newPassword) {
                return newPassword
            }
            print("Failed to save password to Keychain")
            return nil
        case .cancelled:
            return nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DiskImageManager.shared.unmount()
    }

    private func updateIcon() {
        if let button = statusItem.button {
            let symbolName = isCollecting ? "keyboard.badge.ellipsis" : "keyboard"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Panappticon")
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        let shortcut = SettingsManager.shared.toggleShortcut
        let toggleTitle = isCollecting ? "Stop Collecting" : "Start Collecting"
        let toggleItem = NSMenuItem(title: "\(toggleTitle)  \(shortcut.displayString)", action: #selector(toggleCollecting), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let showScreenshotsItem = NSMenuItem(title: "Show Screenshots", action: #selector(showScreenshots), keyEquivalent: "")
        showScreenshotsItem.target = self
        menu.addItem(showScreenshotsItem)

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleCollecting() {
        if isCollecting {
            KeystrokeMonitor.shared.stop()
            MediaMonitor.shared.stop()
            ScreenshotMonitor.shared.stop()
            isCollecting = false
        } else {
            if !checkAccessibilityPermissions() {
                return
            }
            KeystrokeMonitor.shared.start()
            MediaMonitor.shared.start()
            ScreenshotMonitor.shared.start()
            isCollecting = true
        }
        updateIcon()
        buildMenu()
    }

    @objc private func showScreenshots() {
        NSWorkspace.shared.open(DiskImageManager.shared.screenshotDirectory)
    }

    @objc private func openSettings() {
        SettingsManager.shared.openConfig()
    }

    private func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @objc private func quitApp() {
        if isCollecting {
            KeystrokeMonitor.shared.stop()
            MediaMonitor.shared.stop()
            ScreenshotMonitor.shared.stop()
        }
        HotkeyManager.shared.stop()
        DiskImageManager.shared.unmount()
        DatabaseManager.shared.close()
        NSApplication.shared.terminate(nil)
    }
}
