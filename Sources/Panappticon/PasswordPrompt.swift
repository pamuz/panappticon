import AppKit

enum PasswordPromptResult {
    case password(String)
    case cancelled
}

class PasswordPrompt {
    static func promptForNewPassword() -> PasswordPromptResult {
        let previousPolicy = NSApplication.shared.activationPolicy()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        defer {
            NSApplication.shared.setActivationPolicy(previousPolicy)
        }

        let alert = NSAlert()
        alert.messageText = "Set Database Password"
        alert.informativeText = "Choose a password to encrypt your data. Minimum 8 characters. You will need this password if you access the database from another tool."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 62))

        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 34, width: 300, height: 24))
        passwordField.placeholderString = "Password"
        containerView.addSubview(passwordField)

        let confirmField = NSSecureTextField(frame: NSRect(x: 0, y: 2, width: 300, height: 24))
        confirmField.placeholderString = "Confirm password"
        containerView.addSubview(confirmField)

        alert.accessoryView = containerView
        alert.window.initialFirstResponder = passwordField

        while true {
            let response = alert.runModal()

            if response == .alertSecondButtonReturn {
                return .cancelled
            }

            let password = passwordField.stringValue
            let confirm = confirmField.stringValue

            if password.isEmpty {
                showError("Password cannot be empty.")
                continue
            }

            if password.count < 8 {
                showError("Password must be at least 8 characters.")
                continue
            }

            if password != confirm {
                showError("Passwords do not match.")
                confirmField.stringValue = ""
                continue
            }

            return .password(password)
        }
    }

    private static func showError(_ message: String) {
        let errorAlert = NSAlert()
        errorAlert.messageText = "Invalid Password"
        errorAlert.informativeText = message
        errorAlert.alertStyle = .warning
        errorAlert.addButton(withTitle: "OK")
        errorAlert.runModal()
    }
}
