import Foundation

final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    let logDirectoryURL: URL
    let logFileURL: URL
    private let legacyLogFileURL: URL

    private let queue = DispatchQueue(label: "MacClipper.logger")
    private let formatter = ISO8601DateFormatter()
    private let fileManager = FileManager.default

    private init() {
        logDirectoryURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MacClipper", isDirectory: true)
        logFileURL = logDirectoryURL.appendingPathComponent("capture.log", isDirectory: false)
        legacyLogFileURL = logDirectoryURL.appendingPathComponent("replay-buffer.log", isDirectory: false)
        formatter.formatOptions = [.withInternetDateTime]
        ensureLogDirectoryExists()
    }

    func log(_ category: String, _ message: String) {
        queue.async {
            let line = "[\(self.formatter.string(from: Date()))] [\(category)] \(message)\n"
            self.append(line: line)
        }
    }

    func readLog(maxCharacters: Int = 120_000) -> String {
        queue.sync {
            ensureLogDirectoryExists()

            let currentData = try? Data(contentsOf: logFileURL)
            let legacyData = try? Data(contentsOf: legacyLogFileURL)
            let resolvedData = currentData?.isEmpty == false ? currentData : (legacyData?.isEmpty == false ? legacyData : nil)

            guard let data = resolvedData else {
                return "No diagnostics logs yet. Try clipping again, then refresh this panel."
            }

            let logText = String(decoding: data, as: UTF8.self)
            guard logText.count > maxCharacters else {
                return logText
            }

            return "[log truncated to last \(maxCharacters) characters]\n" + String(logText.suffix(maxCharacters))
        }
    }

    func clearLog() {
        queue.sync {
            try? fileManager.removeItem(at: logFileURL)
            try? fileManager.removeItem(at: legacyLogFileURL)
        }
    }

    private func append(line: String) {
        ensureLogDirectoryExists()
        let data = Data(line.utf8)

        if fileManager.fileExists(atPath: logFileURL.path),
           let handle = try? FileHandle(forWritingTo: logFileURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
            return
        }

        try? data.write(to: logFileURL, options: .atomic)
    }

    private func ensureLogDirectoryExists() {
        try? fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
    }
}