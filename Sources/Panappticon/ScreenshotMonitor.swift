import AppKit
import CoreGraphics
import ImageIO

class ScreenshotMonitor {
    static let shared = ScreenshotMonitor()

    private var timer: Timer?
    private var hasCheckedPermission = false
    private let screenshotDir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        screenshotDir = appSupport.appendingPathComponent("Panappticon/screenshots")
        try? FileManager.default.createDirectory(at: screenshotDir, withIntermediateDirectories: true)
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.captureScreenshots()
        }
        captureScreenshots()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func captureScreenshots() {
        if !hasCheckedPermission {
            hasCheckedPermission = true
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
                return
            }
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let now = Date()
        let timestamp = formatter.string(from: now)
        let safeTimestamp = timestamp.replacingOccurrences(of: ":", with: "-")

        let activeApp: String
        let activeBundle: String
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            activeApp = frontmost.localizedName ?? ""
            activeBundle = frontmost.bundleIdentifier ?? ""
        } else {
            activeApp = ""
            activeBundle = ""
        }

        for (index, screen) in NSScreen.screens.enumerated() {
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            guard let image = CGDisplayCreateImage(displayID) else { continue }

            let filename = "screenshot_\(safeTimestamp)_display\(index).jpg"
            let fileURL = screenshotDir.appendingPathComponent(filename)

            guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, "public.jpeg" as CFString, 1, nil) else { continue }
            let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.7]
            CGImageDestinationAddImage(destination, image, options as CFDictionary)

            if CGImageDestinationFinalize(destination) {
                DatabaseManager.shared.insertScreenshot(
                    filename: filename,
                    displayIndex: index,
                    activeApp: activeApp,
                    activeBundle: activeBundle,
                    timestamp: timestamp
                )
            }
        }
    }
}
