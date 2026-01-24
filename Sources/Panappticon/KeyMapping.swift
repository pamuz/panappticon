import Foundation
import CoreGraphics

struct KeyMapping {
    private static let specialKeys: [Int: String] = [
        36: "Return",
        48: "Tab",
        49: "Space",
        51: "Delete",
        53: "Escape",
        76: "Enter",
        115: "Home",
        116: "PageUp",
        117: "ForwardDelete",
        119: "End",
        121: "PageDown",
        123: "LeftArrow",
        124: "RightArrow",
        125: "DownArrow",
        126: "UpArrow",
        122: "F1",
        120: "F2",
        99: "F3",
        118: "F4",
        96: "F5",
        97: "F6",
        98: "F7",
        100: "F8",
        101: "F9",
        109: "F10",
        103: "F11",
        111: "F12",
    ]

    static func characterForEvent(_ event: CGEvent, keyCode: Int) -> String {
        if let special = specialKeys[keyCode] {
            return "[\(special)]"
        }

        var length: Int = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)

        if length > 0 {
            return String(utf16CodeUnits: chars, count: length)
        }

        return "[Key:\(keyCode)]"
    }
}
