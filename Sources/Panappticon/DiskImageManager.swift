import Foundation

class DiskImageManager {
    static let shared = DiskImageManager()

    private var isMounted = false

    private var dataDir: URL {
        return SettingsManager.shared.dataPath
    }

    private var imagePath: URL {
        return dataDir.appendingPathComponent("screenshots.sparsebundle")
    }

    private var mountPoint: URL {
        return dataDir.appendingPathComponent(".screenshots_mount")
    }

    var screenshotDirectory: URL {
        return mountPoint
    }

    private init() {
        installSignalHandlers()
    }

    func initialize(password: String) {
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        if isAlreadyMounted() {
            isMounted = true
            return
        }

        let imageExists = FileManager.default.fileExists(atPath: imagePath.path)

        if !imageExists {
            let created = createImage(password: password)
            if !created {
                print("Failed to create encrypted disk image")
                return
            }
        }

        let mounted = mount(password: password)
        if !mounted {
            print("Failed to mount encrypted disk image")
        }
    }

    func unmount() {
        guard isMounted else { return }
        let result = runHdiutil(arguments: ["detach", mountPoint.path])
        if result {
            isMounted = false
        }
    }

    private func createImage(password: String) -> Bool {
        try? FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        return runHdiutil(
            arguments: [
                "create",
                "-size", "50g",
                "-type", "SPARSEBUNDLE",
                "-encryption", "AES-256",
                "-fs", "APFS",
                "-volname", "PanappticonScreenshots",
                "-stdinpass",
                imagePath.path
            ],
            input: password
        )
    }

    private func mount(password: String) -> Bool {
        try? FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let result = runHdiutil(
            arguments: [
                "attach",
                imagePath.path,
                "-mountpoint", mountPoint.path,
                "-stdinpass",
                "-nobrowse",
                "-noautoopen"
            ],
            input: password
        )
        if result {
            isMounted = true
        }
        return result
    }

    private func isAlreadyMounted() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount")
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return false }
        return output.contains(mountPoint.path)
    }

    @discardableResult
    private func runHdiutil(arguments: [String], input: String? = nil) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice

        if let input = input {
            let inputPipe = Pipe()
            process.standardInput = inputPipe
            do {
                try process.run()
                inputPipe.fileHandleForWriting.write(input.data(using: .utf8)!)
                inputPipe.fileHandleForWriting.closeFile()
            } catch {
                print("hdiutil failed: \(error)")
                return false
            }
        } else {
            do {
                try process.run()
            } catch {
                print("hdiutil failed: \(error)")
                return false
            }
        }

        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func installSignalHandlers() {
        let handler: @convention(c) (Int32) -> Void = { _ in
            DiskImageManager.shared.unmount()
            exit(0)
        }
        signal(SIGTERM, handler)
        signal(SIGINT, handler)
    }
}
