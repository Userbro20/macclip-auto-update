import Darwin
import Foundation

final class DiscordRichPresenceManager: @unchecked Sendable {
    private enum OpCode: Int32 {
        case handshake = 0
        case frame = 1
    }

    private struct Configuration {
        let clientID: String
        let macClipperImageKey: String?
        let macClipperImageText: String?
        let buttons: [[String: String]]
    }

    private struct PresenceContext: Equatable {
        let details: String
        let largeImageKey: String?
        let largeImageText: String?
        let smallImageKey: String?
        let smallImageText: String?
    }

    private let queue = DispatchQueue(label: "MacClipper.discord-rich-presence")
    private let launchedAt = Date()

    private var socketFileDescriptor: Int32 = -1
    private var syncTimer: DispatchSourceTimer?
    private var isStarted = false
    private var didResolveConfiguration = false
    private var cachedConfiguration: Configuration?
    private var lastPublishedContext: PresenceContext?

    func start() {
        queue.async { [weak self] in
            self?.startLocked()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopLocked()
        }
    }

    private func startLocked() {
        guard !isStarted else { return }
        isStarted = true
        scheduleSyncTimerLocked()
        syncPresenceLocked()
    }

    private func stopLocked() {
        isStarted = false
        syncTimer?.cancel()
        syncTimer = nil
        closeSocketLocked()
    }

    private func scheduleSyncTimerLocked() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(5), repeating: .seconds(5))
        timer.setEventHandler { [weak self] in
            self?.syncPresenceLocked()
        }
        syncTimer = timer
        timer.resume()
    }

    private func syncPresenceLocked() {
        guard isStarted, let configuration = configurationLocked() else { return }
        let context = Self.makePresenceContext(using: configuration)

        if socketFileDescriptor == -1 && !connectLocked(using: configuration) {
            return
        }

        guard context != lastPublishedContext else { return }

        do {
            try sendActivityLocked(configuration: configuration, context: context)
            lastPublishedContext = context
            drainAvailableFramesLocked()
        } catch {
            log("rich presence sync failed: \(error.localizedDescription)")
            closeSocketLocked()
        }
    }

    private func configurationLocked() -> Configuration? {
        if didResolveConfiguration {
            return cachedConfiguration
        }

        didResolveConfiguration = true
        cachedConfiguration = Self.loadConfiguration()

        if cachedConfiguration == nil {
            log("rich presence disabled: set a valid DiscordRichPresenceClientID in AppResources/Info.plist")
        }

        return cachedConfiguration
    }

    private static func loadConfiguration() -> Configuration? {
        let bundle = Bundle.main
        guard let clientID = bundle.trimmedInfoString(forKey: "DiscordRichPresenceClientID"),
              clientID.range(of: "^[0-9]{10,}$", options: .regularExpression) != nil else {
            return nil
        }
        let macClipperImageKey = bundle.trimmedInfoString(forKey: "DiscordRichPresenceLargeImageKey")
        let macClipperImageText = bundle.trimmedInfoString(forKey: "DiscordRichPresenceLargeImageText")

        var buttons: [[String: String]] = []
        buttons.reserveCapacity(2)

        if let firstLabel = bundle.trimmedInfoString(forKey: "DiscordRichPresenceButton1Label"),
           let firstURL = bundle.trimmedInfoString(forKey: "DiscordRichPresenceButton1URL") {
            buttons.append(["label": firstLabel, "url": firstURL])
        }

        if let secondLabel = bundle.trimmedInfoString(forKey: "DiscordRichPresenceButton2Label"),
           let secondURL = bundle.trimmedInfoString(forKey: "DiscordRichPresenceButton2URL") {
            buttons.append(["label": secondLabel, "url": secondURL])
        }

        return Configuration(
            clientID: clientID,
            macClipperImageKey: macClipperImageKey,
            macClipperImageText: macClipperImageText,
            buttons: buttons
        )
    }

    private static func makePresenceContext(using configuration: Configuration) -> PresenceContext {
        let sourceApp = CaptureSourceAppDetector.captureCurrentSourceApp(bundleIdentifier: Bundle.main.bundleIdentifier)
        let subject = sourceApp.isDesktopCapture ? "Desktop" : sourceApp.name
        let details = "Clipping \(subject) with MacClipper"

        if sourceApp.isDesktopCapture {
            return PresenceContext(
                details: details,
                largeImageKey: configuration.macClipperImageKey,
                largeImageText: configuration.macClipperImageText ?? "MacClipper",
                smallImageKey: nil,
                smallImageText: nil
            )
        }

        return PresenceContext(
            details: details,
            largeImageKey: CaptureSourceAppDetector.discordAssetKey(for: sourceApp),
            largeImageText: sourceApp.name,
            smallImageKey: configuration.macClipperImageKey,
            smallImageText: configuration.macClipperImageText ?? "MacClipper"
        )
    }

    private func connectLocked(using configuration: Configuration) -> Bool {
        for socketPath in Self.socketPaths() {
            guard let descriptor = Self.openSocket(at: socketPath) else {
                continue
            }

            socketFileDescriptor = descriptor

            do {
                try sendHandshakeLocked(clientID: configuration.clientID)
                log("rich presence connected")
                return true
            } catch {
                closeSocketLocked()
            }
        }

        return false
    }

    private static func socketPaths() -> [String] {
        let environment = ProcessInfo.processInfo.environment
        let candidateRoots: [String?] = [
            environment["XDG_RUNTIME_DIR"],
            environment["TMPDIR"],
            environment["TMP"],
            environment["TEMP"],
            FileManager.default.temporaryDirectory.path,
            "/tmp",
            "/var/tmp"
        ]

        var uniqueRoots: [String] = []
        var seenRoots: Set<String> = []

        for root in candidateRoots.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            let normalizedRoot = URL(fileURLWithPath: (root as NSString).expandingTildeInPath, isDirectory: true).path
            if seenRoots.insert(normalizedRoot).inserted {
                uniqueRoots.append(normalizedRoot)
            }
        }

        return uniqueRoots.flatMap { root in
            (0 ..< 10).map { index in
                URL(fileURLWithPath: root, isDirectory: true)
                    .appendingPathComponent("discord-ipc-\(index)")
                    .path
            }
        }
    }

    private static func openSocket(at path: String) -> Int32? {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            return nil
        }

        var noSigPipe: Int32 = 1
        withUnsafePointer(to: &noSigPipe) {
            _ = setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                $0,
                socklen_t(MemoryLayout<Int32>.size)
            )
        }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        withUnsafePointer(to: &timeout) {
            _ = setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_RCVTIMEO,
                $0,
                socklen_t(MemoryLayout<timeval>.size)
            )
            _ = setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_SNDTIMEO,
                $0,
                socklen_t(MemoryLayout<timeval>.size)
            )
        }

        var address = sockaddr_un()
#if os(macOS)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
#endif
        address.sun_family = sa_family_t(AF_UNIX)

        let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < maxPathLength else {
            close(descriptor)
            return nil
        }

        path.withCString { pathCString in
            withUnsafeMutablePointer(to: &address.sun_path) { pointer in
                let rawPointer = UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self)
                strncpy(rawPointer, pathCString, maxPathLength - 1)
            }
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard result == 0 else {
            close(descriptor)
            return nil
        }

        return descriptor
    }

    private func sendHandshakeLocked(clientID: String) throws {
        try sendFrameLocked(opCode: .handshake, object: [
            "v": 1,
            "client_id": clientID
        ])
        _ = try readFrameLocked()
    }

    private func sendActivityLocked(configuration: Configuration, context: PresenceContext) throws {
        var activity: [String: Any] = [
            "type": 0,
            "details": context.details,
            "timestamps": [
                "start": Int(launchedAt.timeIntervalSince1970)
            ]
        ]

        var assets: [String: String] = [:]
        if let largeImageKey = context.largeImageKey {
            assets["large_image"] = largeImageKey
        }
        if let largeImageText = context.largeImageText {
            assets["large_text"] = largeImageText
        }
        if let smallImageKey = context.smallImageKey {
            assets["small_image"] = smallImageKey
        }
        if let smallImageText = context.smallImageText {
            assets["small_text"] = smallImageText
        }
        if !assets.isEmpty {
            activity["assets"] = assets
        }

        if !configuration.buttons.isEmpty {
            activity["buttons"] = Array(configuration.buttons.prefix(2))
        }

        try sendFrameLocked(opCode: .frame, object: [
            "cmd": "SET_ACTIVITY",
            "args": [
                "pid": Int(ProcessInfo.processInfo.processIdentifier),
                "activity": activity
            ],
            "nonce": UUID().uuidString
        ])
    }

    private func sendFrameLocked(opCode: OpCode, object: Any) throws {
        guard socketFileDescriptor >= 0 else {
            throw Self.makeError("Discord RPC socket is not connected.")
        }

        let payloadData = try JSONSerialization.data(withJSONObject: object)
        var frameData = Data()
        var opCodeValue = opCode.rawValue.littleEndian
        var payloadLength = Int32(payloadData.count).littleEndian

        withUnsafeBytes(of: &opCodeValue) { frameData.append(contentsOf: $0) }
        withUnsafeBytes(of: &payloadLength) { frameData.append(contentsOf: $0) }
        frameData.append(payloadData)

        try writeLocked(data: frameData)
    }

    private func writeLocked(data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }

            var bytesWritten = 0
            while bytesWritten < rawBuffer.count {
                let written = send(
                    socketFileDescriptor,
                    baseAddress.advanced(by: bytesWritten),
                    rawBuffer.count - bytesWritten,
                    0
                )

                if written <= 0 {
                    throw Self.makeError("Discord RPC write failed.")
                }

                bytesWritten += written
            }
        }
    }

    private func readFrameLocked() throws -> Data {
        let headerData = try readExactlyLocked(length: 8)
        var payloadLengthRaw: Int32 = 0
        _ = withUnsafeMutableBytes(of: &payloadLengthRaw) { headerData.copyBytes(to: $0, from: 4 ..< 8) }
        let payloadLength = Int(Int32(littleEndian: payloadLengthRaw))

        guard payloadLength >= 0 else {
            throw Self.makeError("Discord RPC returned an invalid payload length.")
        }

        return try readExactlyLocked(length: payloadLength)
    }

    private func readExactlyLocked(length: Int) throws -> Data {
        var data = Data(count: length)

        try data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }

            var bytesRead = 0
            while bytesRead < length {
                let readCount = recv(
                    socketFileDescriptor,
                    baseAddress.advanced(by: bytesRead),
                    length - bytesRead,
                    0
                )

                if readCount <= 0 {
                    throw Self.makeError("Discord RPC read failed.")
                }

                bytesRead += readCount
            }
        }

        return data
    }

    private func drainAvailableFramesLocked() {
        guard socketFileDescriptor >= 0 else { return }

        let currentFlags = fcntl(socketFileDescriptor, F_GETFL, 0)
        guard currentFlags >= 0 else { return }

        _ = fcntl(socketFileDescriptor, F_SETFL, currentFlags | O_NONBLOCK)
        defer {
            _ = fcntl(socketFileDescriptor, F_SETFL, currentFlags)
        }

        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = recv(socketFileDescriptor, &buffer, buffer.count, 0)
            if count > 0 {
                continue
            }

            if count == 0 {
                closeSocketLocked()
            }

            break
        }
    }

    private func closeSocketLocked() {
        lastPublishedContext = nil

        guard socketFileDescriptor >= 0 else { return }
        close(socketFileDescriptor)
        socketFileDescriptor = -1
    }

    private static func makeError(_ description: String) -> NSError {
        NSError(domain: "MacClipperDiscordRichPresence", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
    }

    private func log(_ message: String) {
        AppLogger.shared.log("DiscordRPC", message)
    }
}

private extension Bundle {
    func trimmedInfoString(forKey key: String) -> String? {
        guard let rawValue = object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}