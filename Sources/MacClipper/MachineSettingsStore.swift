import Foundation

struct PersistedAppSettings: Codable {
    var clipDuration: Double
    var startReplayBufferOnLaunch: Bool
    var includeMicrophone: Bool
    var selectedMicrophoneID: String?
    var captureSystemAudio: Bool
    var systemAudioLevel: Double?
    var showCursor: Bool
    var enableGameNotifications: Bool
    var captureResolutionPreset: CaptureResolutionPreset
    var videoQualityPreset: VideoQualityPreset
    var appUUID: String?
    var websiteUserID: String?
    var unlockedPaidFeatures: [String]
    var shortcutKey: String
    var useCommand: Bool
    var useShift: Bool
    var useOption: Bool
    var useControl: Bool
    var saveDirectoryPath: String
    var selectedCaptureDisplayID: String
    var discordWebhookURLString: String
    var automaticallyChecksForUpdates: Bool
    var captureDeviceProfiles: [String: CaptureDeviceSettingsProfile]
}

private struct PersistedAppSettingsEnvelope: Codable {
    let schemaVersion: Int
    let machineIdentifier: String?
    let savedAt: Date
    let settings: PersistedAppSettings
}

final class MachineSettingsStore {
    private static let schemaVersion = 1
    private static let settingsFileName = "settings.json"

    let settingsFileURL: URL

    private let fileManager: FileManager
    private let settingsDirectoryURL: URL
    private let legacySettingsDirectoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let baseDirectory = Self.makeSettingsDirectoryURL(fileManager: fileManager)
        settingsDirectoryURL = baseDirectory
        legacySettingsDirectoryURL = baseDirectory.appendingPathComponent("MachineSettings", isDirectory: true)
        settingsFileURL = baseDirectory.appendingPathComponent(Self.settingsFileName, isDirectory: false)
    }

    func loadSettings() -> PersistedAppSettings? {
        if let data = try? Data(contentsOf: settingsFileURL),
           let envelope = try? JSONDecoder().decode(PersistedAppSettingsEnvelope.self, from: data) {
            return envelope.settings
        }

        return migrateLegacySettingsIfNeeded()
    }

    func saveSettings(_ settings: PersistedAppSettings) {
        do {
            try Self.ensureDirectoryExists(at: settingsDirectoryURL, fileManager: fileManager)

            let envelope = PersistedAppSettingsEnvelope(
                schemaVersion: Self.schemaVersion,
                machineIdentifier: nil,
                savedAt: Date(),
                settings: settings
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(envelope)
            try data.write(to: settingsFileURL, options: .atomic)
        } catch {
            NSLog("MacClipper failed to save local settings: \(error.localizedDescription)")
        }
    }

    func updateSettings(_ mutate: (inout PersistedAppSettings) -> Void) {
        guard var settings = loadSettings() else { return }
        mutate(&settings)
        saveSettings(settings)
    }

    private static func makeSettingsDirectoryURL(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("MacClipper", isDirectory: true)
    }

    private static func ensureDirectoryExists(at url: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func migrateLegacySettingsIfNeeded() -> PersistedAppSettings? {
        guard let legacySettings = loadLegacySettings() else { return nil }

        saveSettings(legacySettings)
        cleanupLegacySettingsFiles()
        return legacySettings
    }

    private func loadLegacySettings() -> PersistedAppSettings? {
        guard let legacyFileURL = try? fileManager
            .contentsOfDirectory(at: legacySettingsDirectoryURL, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension.lowercased() == "json" }),
            let data = try? Data(contentsOf: legacyFileURL),
            let envelope = try? JSONDecoder().decode(PersistedAppSettingsEnvelope.self, from: data) else {
            return nil
        }

        return envelope.settings
    }

    private func cleanupLegacySettingsFiles() {
        guard let legacyFiles = try? fileManager.contentsOfDirectory(
            at: legacySettingsDirectoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for fileURL in legacyFiles {
            try? fileManager.removeItem(at: fileURL)
        }

        try? fileManager.removeItem(at: legacySettingsDirectoryURL)
    }
}