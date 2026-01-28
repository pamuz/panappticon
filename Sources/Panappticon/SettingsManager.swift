import AppKit
import Carbon

class SettingsManager {
    static let shared = SettingsManager()

    private let configURL: URL
    private var lastModified: Date?

    private(set) var toggleShortcut: KeyboardShortcut = .defaultToggle
    private(set) var collectKeystrokes: Bool = false
    private(set) var collectScreenshots: Bool = false
    private(set) var collectMedia: Bool = false
    private(set) var dataPath: URL

    private let defaultDataPath: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Panappticon")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        configURL = appDir.appendingPathComponent("config")
        defaultDataPath = appDir
        dataPath = appDir

        ensureConfigExists()
        reload()
    }

    private func ensureConfigExists() {
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }

        let defaultConfig = """
            # Panappticon Configuration
            #
            # Keyboard shortcut syntax:
            #   Modifiers: ctrl, opt (or alt), shift, cmd (or super)
            #   Combine with +, e.g.: ctrl+opt+p, cmd+shift+s
            #
            # The shortcut must include at least one modifier.

            toggle_collecting = ctrl+opt+p

            # Data collection settings (opt-in, set to true to enable)
            collect_keystrokes = false
            collect_screenshots = false
            collect_media = false

            # Storage location for database and screenshots (optional)
            # If not set, defaults to ~/Library/Application Support/Panappticon
            # data_path = /path/to/data/folder
            """

        try? defaultConfig.write(to: configURL, atomically: true, encoding: .utf8)
    }

    func reload() {
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else { return }

        // Reset to defaults before parsing
        dataPath = defaultDataPath

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "toggle_collecting":
                if let shortcut = KeyboardShortcut.parse(value) {
                    toggleShortcut = shortcut
                }
            case "collect_keystrokes":
                collectKeystrokes = parseBool(value)
            case "collect_screenshots":
                collectScreenshots = parseBool(value)
            case "collect_media":
                collectMedia = parseBool(value)
            case "data_path":
                if let path = parsePath(value) {
                    dataPath = path
                }
            default:
                break
            }
        }

        lastModified = try? FileManager.default.attributesOfItem(atPath: configURL.path)[.modificationDate] as? Date
    }

    private func parseBool(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return lowercased == "true" || lowercased == "yes" || lowercased == "1"
    }

    private func parsePath(_ value: String) -> URL? {
        let expanded = NSString(string: value).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded, isDirectory: true)

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        // Verify it's a valid directory
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return url
    }

    func openConfig() {
        NSWorkspace.shared.open(configURL)
    }

    func checkForChanges() {
        guard let currentMod = try? FileManager.default.attributesOfItem(atPath: configURL.path)[.modificationDate] as? Date else { return }
        if lastModified != currentMod {
            reload()
        }
    }
}

struct KeyboardShortcut: Equatable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags

    static let defaultToggle = KeyboardShortcut(
        keyCode: UInt16(kVK_ANSI_P),
        modifiers: [.control, .option]
    )

    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        if let keyString = Self.keyCodeToString(keyCode) {
            parts.append(keyString)
        }
        return parts.joined()
    }

    static func parse(_ str: String) -> KeyboardShortcut? {
        let parts = str.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { return nil }

        var modifiers: NSEvent.ModifierFlags = []
        var keyPart: String?

        for part in parts {
            switch part {
            case "ctrl", "control", "c":
                modifiers.insert(.control)
            case "opt", "option", "alt", "meta", "m":
                modifiers.insert(.option)
            case "shift", "s":
                modifiers.insert(.shift)
            case "cmd", "command", "super":
                modifiers.insert(.command)
            default:
                keyPart = part
            }
        }

        guard let key = keyPart, let keyCode = stringToKeyCode(key), !modifiers.isEmpty else {
            return nil
        }

        return KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    private static func stringToKeyCode(_ str: String) -> UInt16? {
        let keyMap: [String: UInt16] = [
            "a": UInt16(kVK_ANSI_A), "b": UInt16(kVK_ANSI_B), "c": UInt16(kVK_ANSI_C),
            "d": UInt16(kVK_ANSI_D), "e": UInt16(kVK_ANSI_E), "f": UInt16(kVK_ANSI_F),
            "g": UInt16(kVK_ANSI_G), "h": UInt16(kVK_ANSI_H), "i": UInt16(kVK_ANSI_I),
            "j": UInt16(kVK_ANSI_J), "k": UInt16(kVK_ANSI_K), "l": UInt16(kVK_ANSI_L),
            "m": UInt16(kVK_ANSI_M), "n": UInt16(kVK_ANSI_N), "o": UInt16(kVK_ANSI_O),
            "p": UInt16(kVK_ANSI_P), "q": UInt16(kVK_ANSI_Q), "r": UInt16(kVK_ANSI_R),
            "s": UInt16(kVK_ANSI_S), "t": UInt16(kVK_ANSI_T), "u": UInt16(kVK_ANSI_U),
            "v": UInt16(kVK_ANSI_V), "w": UInt16(kVK_ANSI_W), "x": UInt16(kVK_ANSI_X),
            "y": UInt16(kVK_ANSI_Y), "z": UInt16(kVK_ANSI_Z),
            "0": UInt16(kVK_ANSI_0), "1": UInt16(kVK_ANSI_1), "2": UInt16(kVK_ANSI_2),
            "3": UInt16(kVK_ANSI_3), "4": UInt16(kVK_ANSI_4), "5": UInt16(kVK_ANSI_5),
            "6": UInt16(kVK_ANSI_6), "7": UInt16(kVK_ANSI_7), "8": UInt16(kVK_ANSI_8),
            "9": UInt16(kVK_ANSI_9),
            "space": UInt16(kVK_Space),
            "return": UInt16(kVK_Return), "enter": UInt16(kVK_Return),
            "tab": UInt16(kVK_Tab),
            "escape": UInt16(kVK_Escape), "esc": UInt16(kVK_Escape),
            "delete": UInt16(kVK_Delete), "backspace": UInt16(kVK_Delete),
            "left": UInt16(kVK_LeftArrow), "right": UInt16(kVK_RightArrow),
            "up": UInt16(kVK_UpArrow), "down": UInt16(kVK_DownArrow),
            "f1": UInt16(kVK_F1), "f2": UInt16(kVK_F2), "f3": UInt16(kVK_F3),
            "f4": UInt16(kVK_F4), "f5": UInt16(kVK_F5), "f6": UInt16(kVK_F6),
            "f7": UInt16(kVK_F7), "f8": UInt16(kVK_F8), "f9": UInt16(kVK_F9),
            "f10": UInt16(kVK_F10), "f11": UInt16(kVK_F11), "f12": UInt16(kVK_F12),
        ]
        return keyMap[str]
    }

    private static func keyCodeToString(_ keyCode: UInt16) -> String? {
        let keyMap: [UInt16: String] = [
            UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B", UInt16(kVK_ANSI_C): "C",
            UInt16(kVK_ANSI_D): "D", UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
            UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H", UInt16(kVK_ANSI_I): "I",
            UInt16(kVK_ANSI_J): "J", UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
            UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N", UInt16(kVK_ANSI_O): "O",
            UInt16(kVK_ANSI_P): "P", UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
            UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T", UInt16(kVK_ANSI_U): "U",
            UInt16(kVK_ANSI_V): "V", UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
            UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
            UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2",
            UInt16(kVK_ANSI_3): "3", UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
            UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8",
            UInt16(kVK_ANSI_9): "9",
            UInt16(kVK_Space): "Space",
            UInt16(kVK_Return): "↩",
            UInt16(kVK_Tab): "⇥",
            UInt16(kVK_Escape): "⎋",
            UInt16(kVK_Delete): "⌫",
            UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
            UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
            UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
            UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
            UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        ]
        return keyMap[keyCode]
    }
}
