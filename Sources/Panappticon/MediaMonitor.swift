import Foundation

class MediaMonitor {
    static let shared = MediaMonitor()

    private var currentTitle: String?

    private var helperProcess: Process?
    private var outputPipe: Pipe?

    private init() {}

    func start() {
        guard helperProcess == nil else { return }
        startHelper()
    }

    func stop() {
        helperProcess?.terminate()
        helperProcess = nil
        outputPipe = nil
        currentTitle = nil
    }

    private func startHelper() {
        let scriptPath = writeHelperScript()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [scriptPath]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        // Read output lines asynchronously
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let line = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.handleHelperOutput(line)
                }
            }
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self?.helperProcess = nil
                self?.startHelper()
            }
        }

        do {
            try process.run()
        } catch {
            print("[MediaMonitor] Failed to start helper: \(error)")
            return
        }

        helperProcess = process
        outputPipe = pipe
    }

    private func handleHelperOutput(_ rawOutput: String) {
        // Each line is a JSON object
        for line in rawOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard trimmed.hasPrefix("{") else { continue }

            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            processNowPlayingInfo(json)
        }
    }

    private func processNowPlayingInfo(_ info: [String: Any]) {
        let title = info["title"] as? String ?? ""
        let artist = info["artist"] as? String ?? ""
        let album = info["album"] as? String ?? ""
        let sourceApp = info["bundleId"] as? String ?? ""
        let isEmpty = info["empty"] as? Bool ?? false

        if isEmpty || title.isEmpty {
            currentTitle = nil
            return
        }

        if title != currentTitle {
            print("[MediaMonitor] Now playing: \"\(title)\" by \(artist) [\(sourceApp)]")

            let now = ISO8601DateFormatter().string(from: Date())
            DatabaseManager.shared.insertMedia(
                title: title,
                artist: artist,
                album: album,
                sourceApp: sourceApp,
                timestamp: now
            )
            currentTitle = title
        }
    }

    private func writeHelperScript() -> String {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Panappticon")
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

        let scriptURL = supportDir.appendingPathComponent("media-helper.swift")
        let script = """
        import Foundation

        typealias MRGetInfoFunc = @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void
        typealias MRGetClientFunc = @convention(c) (DispatchQueue, @escaping @convention(block) (AnyObject?) -> Void) -> Void
        typealias MRRegisterFunc = @convention(c) (DispatchQueue) -> Void

        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY) else {
            fputs("FATAL: cannot load MediaRemote\\n", stderr)
            exit(1)
        }

        if let regSym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            let regFn = unsafeBitCast(regSym, to: MRRegisterFunc.self)
            regFn(DispatchQueue.main)
        }

        guard let infoSym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else {
            fputs("FATAL: cannot find MRMediaRemoteGetNowPlayingInfo\\n", stderr)
            exit(1)
        }
        let getInfoFn = unsafeBitCast(infoSym, to: MRGetInfoFunc.self)

        var getClientFn: MRGetClientFunc? = nil
        if let clientSym = dlsym(handle, "MRMediaRemoteGetNowPlayingClient") {
            getClientFn = unsafeBitCast(clientSym, to: MRGetClientFunc.self)
        }

        func loadKey(_ name: String) -> String {
            guard let ptr = dlsym(handle, name) else { return name }
            guard let raw = ptr.load(as: UnsafeRawPointer?.self) else { return name }
            return Unmanaged<NSString>.fromOpaque(raw).takeUnretainedValue() as String
        }

        let titleKey = loadKey("kMRMediaRemoteNowPlayingInfoTitle")
        let artistKey = loadKey("kMRMediaRemoteNowPlayingInfoArtist")
        let albumKey = loadKey("kMRMediaRemoteNowPlayingInfoAlbum")

        print("READY")
        fflush(stdout)

        func emit(_ dict: [String: Any]) {
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let str = String(data: data, encoding: .utf8) {
                print(str)
                fflush(stdout)
            }
        }

        func poll() {
            getInfoFn(DispatchQueue.main) { rawInfo in
                guard let info = rawInfo as? [String: Any], !info.isEmpty else {
                    emit(["empty": true])
                    return
                }

                let title = info[titleKey] as? String ?? ""
                let artist = info[artistKey] as? String ?? ""
                let album = info[albumKey] as? String ?? ""

                // Get bundle ID from the now-playing client
                if let clientFn = getClientFn {
                    clientFn(DispatchQueue.main) { client in
                        let bundleId = client?.value(forKey: "bundleIdentifier") as? String ?? ""
                        emit(["title": title, "artist": artist, "album": album, "bundleId": bundleId])
                    }
                } else {
                    emit(["title": title, "artist": artist, "album": album, "bundleId": ""])
                }
            }
        }

        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            poll()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            poll()
        }

        RunLoop.main.run()
        """

        try? script.write(to: scriptURL, atomically: true, encoding: .utf8)
        return scriptURL.path
    }
}
