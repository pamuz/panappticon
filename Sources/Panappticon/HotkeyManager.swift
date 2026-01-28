import AppKit

class HotkeyManager {
    static let shared = HotkeyManager()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var onToggle: (() -> Void)?

    private init() {}

    func start(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        stop()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil
            }
            return event
        }
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        SettingsManager.shared.checkForChanges()

        let shortcut = SettingsManager.shared.toggleShortcut
        let relevantModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        let eventModifiers = event.modifierFlags.intersection(relevantModifiers)

        if event.keyCode == shortcut.keyCode && eventModifiers == shortcut.modifiers {
            onToggle?()
            return true
        }
        return false
    }
}
