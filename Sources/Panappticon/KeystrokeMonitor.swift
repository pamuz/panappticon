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
    
    let modifierMap: [(CGEventFlags, String)] = [
        (.maskControl, "Ctrl"),
        (.maskAlternate, "Alt"),
        (.maskShift, "Shift"),
        (.maskCommand, "Cmd")
    ]
    
    let modifiers = modifierMap
        .filter { flags.contains($0.0) }
        .map { $0.1 }
    
    let keystroke = (modifiers + [KeyMapping.characterForEvent(event, keyCode: Int(keyCode))]).joined(separator: "+")
    print(keystroke)
    
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
