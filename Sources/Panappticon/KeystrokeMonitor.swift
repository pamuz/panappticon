import Foundation
import CoreGraphics
import AppKit

private let timestampFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    return formatter
}()

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout {
        KeystrokeMonitor.shared.reenableTap()
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown else {
        return Unmanaged.passUnretained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    let character = KeyMapping.characterForEvent(event, keyCode: Int(keyCode))
    
    // Determine if this is a "significant" key combination
    // If only Shift is pressed with a printable character, omit Shift from the modifier string
    // since Shift is used to produce the character itself (e.g., Shift+' produces ")
    let hasCommandOrControl = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
    let shouldIncludeShift = hasCommandOrControl || character.count > 1 // Multi-char strings are special keys like "Enter", "Tab"
    
    let modifierMap: [(CGEventFlags, String, Bool)] = [
        (.maskControl, "Ctrl", true),
        (.maskAlternate, "Alt", true),
        (.maskShift, "Shift", shouldIncludeShift),
        (.maskCommand, "Cmd", true)
    ]
    
    let modifiers = modifierMap
        .filter { flags.contains($0.0) && $0.2 }
        .map { $0.1 }
    
    let keystroke = (modifiers + [character]).joined(separator: "+")
    
    let activeApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
    let timestamp = timestampFormatter.string(from: Date())

    DatabaseManager.shared.insertKeystroke(keystroke: keystroke, timestamp: timestamp, application: activeApp)

    return Unmanaged.passUnretained(event)
}

class KeystrokeMonitor {
    static let shared = KeystrokeMonitor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    func start() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            print("Failed to create event tap. Check Accessibility permissions.")
            return
        }

        eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    func reenableTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
}
