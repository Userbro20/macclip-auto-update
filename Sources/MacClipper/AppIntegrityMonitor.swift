import Foundation
import AppKit

enum AppIntegrityMonitor {
    @MainActor private static var hasPresentedIntegrityAlert = false

    static func verifyCurrentAppBundleAtLaunch() {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        guard bundleURL.pathExtension.lowercased() == "app" else { return }
        guard !bundleURL.path.contains("/.build/") else { return }

        Task.detached(priority: .utility) {
            if let failureMessage = verifyBundleSignature(at: bundleURL) {
                AppLogger.shared.log("Security", "app integrity verification failed message=\(failureMessage)")
                await MainActor.run {
                    presentIntegrityAlertIfNeeded(message: failureMessage)
                }
            } else {
                AppLogger.shared.log("Security", "app integrity verification passed path=\(bundleURL.path)")
            }
        }
    }

    private static func verifyBundleSignature(at bundleURL: URL) -> String? {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", bundleURL.path]
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return error.localizedDescription
        }

        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            return output.isEmpty ? "Code signature verification failed." : output
        }

        return nil
    }

    @MainActor
    private static func presentIntegrityAlertIfNeeded(message: String) {
        guard !hasPresentedIntegrityAlert else { return }
        hasPresentedIntegrityAlert = true

        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "MacClipper Integrity Warning"
        alert.informativeText = "This copy of MacClipper appears to have been modified on disk or its code signature no longer validates.\n\n\(message)\n\nQuit unless you trust this copy."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Continue Anyway")

        if alert.runModal() == .alertFirstButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }
}