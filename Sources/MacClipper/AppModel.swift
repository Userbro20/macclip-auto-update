import Foundation
import AppKit
import AVFoundation
import SwiftUI
import UserNotifications

private struct AppInstallationRegistrationPayload: Encodable {
    let appUuid: String
    let machineIdentifier: String
    let machineName: String
    let machineModel: String
    let systemVersion: String
    let appVersion: String
    let buildVersion: String
}

private struct AppInstallationRegistrationSnapshot: Decodable {
    let installation: RegisteredAppInstallation
}

private struct RegisteredAppInstallation: Decodable {
    let appUuid: String
    let websiteUserID: String

    private enum CodingKeys: String, CodingKey {
        case appUuid
        case websiteUserID = "websiteUserId"
    }
}

struct ClipSourceApp: Codable, Hashable {
    let name: String
    let bundleIdentifier: String?

    var isDesktopCapture: Bool {
        bundleIdentifier == nil && name.caseInsensitiveCompare("Desktop") == .orderedSame
    }
}

private struct ClipMetadata: Codable {
    let sourceApp: ClipSourceApp?
    let capturedAt: Date
}

struct SavedClip: Identifiable, Hashable {
    let url: URL
    let createdAt: Date
    let fileSizeText: String
    let sourceApp: ClipSourceApp?

    var id: URL { url }
}

struct CaptureDisplayOption: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
}

struct MicrophoneOption: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String

    var pickerLabel: String {
        detail.isEmpty ? title : "\(title) • \(detail)"
    }
}

private struct PendingClipRequest: Identifiable {
    let id = UUID()
    let capturePoint: ReplayCapturePoint
    let duration: Int
    let sourceApp: ClipSourceApp?
    let suppressMicrophoneInExport: Bool
}

private struct WebsiteEntitlementSnapshot: Decodable {
    let user: WebsiteEntitlementUser
}

private struct WebsiteEntitlementUser: Decodable {
    let id: String
    let accountStatus: String
    let subscriptionTier: String
    let paidFeatures: [String]
    let updatedAt: String?
}

private enum DiscordShareMode: Equatable {
    case channelUpload
    case directMessageHandoff
}

private enum ClipLibraryLoader {
    static func loadSavedClips(from folderURL: URL) -> [SavedClip] {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        return ClipStorageManager.clipFileURLs(in: folderURL)
            .compactMap { makeSavedClip(from: $0, formatter: formatter) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func makeSavedClip(
        from url: URL,
        fallbackCreatedAt: Date? = nil,
        sourceAppOverride: ClipSourceApp? = nil
    ) -> SavedClip? {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return makeSavedClip(
            from: url,
            fallbackCreatedAt: fallbackCreatedAt,
            sourceAppOverride: sourceAppOverride,
            formatter: formatter
        )
    }

    static func metadataURL(for clipURL: URL) -> URL {
        clipURL
            .deletingPathExtension()
            .appendingPathComponent("metadata", conformingTo: .json)
    }

    static func loadMetadata(for clipURL: URL) -> ClipMetadata? {
        let metadataURL = metadataURL(for: clipURL)
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        return try? JSONDecoder().decode(ClipMetadata.self, from: data)
    }

    private static func makeSavedClip(
        from url: URL,
        fallbackCreatedAt: Date? = nil,
        sourceAppOverride: ClipSourceApp? = nil,
        formatter: ByteCountFormatter
    ) -> SavedClip? {
        let resourceKeys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let values = try? url.resourceValues(forKeys: resourceKeys), values.isRegularFile != false else {
            return nil
        }

        let createdAt = values.creationDate ?? values.contentModificationDate ?? fallbackCreatedAt ?? Date.distantPast
        let fileSizeText = formatter.string(fromByteCount: Int64(values.fileSize ?? 0))
        let sourceApp = sourceAppOverride ?? loadMetadata(for: url)?.sourceApp
        return SavedClip(url: url, createdAt: createdAt, fileSizeText: fileSizeText, sourceApp: sourceApp)
    }
}

struct CaptureDeviceSettingsProfile: Codable {
    let clipDuration: Double
    let includeMicrophone: Bool
    let captureSystemAudio: Bool
    let systemAudioLevel: Double?
    let microphoneAudioLevel: Double?
    let showCursor: Bool
    let captureResolutionPreset: CaptureResolutionPreset
    let videoQualityPreset: VideoQualityPreset
}

@MainActor
final class AppModel: ObservableObject {
    private static let lockedDiscordWebhookURL = "https://discord.com/api/webhooks/1491091224180818160/2MutnrfaVcaH5l2GM-XRhw90z_ec0apc6TQ2Pib_5y_9hxP3Q3uPhRUhmlc4bMhfI0RW"
    private static let captureDeviceProfilesKey = "captureDeviceProfiles"
    private static let defaultPurchasePortalURLString = "http://127.0.0.1:4173/buy-4k.html"

    @Published var statusText: String = "Capture ready"
    @Published var isRecording: Bool = false
    @Published var isBusy: Bool = false
    @Published var lastClipURL: URL?
    @Published var clips: [SavedClip] = []
    @Published var selectedClip: SavedClip?

    @Published var clipDuration: Double
    @Published var startReplayBufferOnLaunch: Bool
    @Published var includeMicrophone: Bool
    @Published var selectedMicrophoneID: String
    @Published var captureSystemAudio: Bool
    @Published var systemAudioLevel: Double
    @Published var microphoneAudioLevel: Double
    @Published var showCursor: Bool
    @Published var enableGameNotifications: Bool
    @Published var captureResolutionPreset: CaptureResolutionPreset
    @Published var videoQualityPreset: VideoQualityPreset
    @Published var appUUID: String
    @Published var websiteUserID: String
    @Published var unlockedPaidFeatures: [String]
    @Published var shortcutKey: String
    @Published var useCommand: Bool
    @Published var useShift: Bool
    @Published var useOption: Bool
    @Published var useControl: Bool
    @Published var saveDirectoryPath: String
    @Published var selectedCaptureDisplayID: String
    @Published var discordWebhookURLString: String
    @Published var diagnosticsLogText: String = ""
    @Published var diagnosticsLogStatusText: String = "Refresh to load the latest diagnostics log."

    let updater: UpdaterManager

    private let defaults = UserDefaults.standard
    private let settingsStore: MachineSettingsStore
    private let recorder = ReplayBufferRecorder()
    private let discordWebhookManager = DiscordWebhookManager()
    private let hotkeyManager = HotkeyManager()
    private let voiceCommandManager = VoiceCommandManager()
    private var notificationObservers: [NSObjectProtocol] = []
    private var pendingClipRequests: [PendingClipRequest] = []
    private var activeClipRequest: PendingClipRequest?
    private var isProcessingClipQueue = false
    private var activeDiscordUploadPaths: Set<String> = []
    private var lastWarmupNotificationAt: Date?
    private var didAttemptInitialRecording = false
    private var isRecoveringRecorder = false
    private var shouldRetryAutomaticStart = false
    private var reloadClipsTask: Task<Void, Never>?
    private var captureDeviceProfiles: [String: CaptureDeviceSettingsProfile] = [:]
    private var microphoneCaptureSuppressed = false
    private var automaticRearmTask: Task<Void, Never>?
    private var entitlementSyncTask: Task<Void, Never>?
    private var appInstallationRegistrationTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        let defaultSaveDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/MacClipper", isDirectory: true)
            .path

        let settingsStore = MachineSettingsStore()
        let persistedSettings = Self.loadPersistedSettings(
            from: settingsStore,
            defaults: defaults,
            defaultSaveDirectory: defaultSaveDirectory
        )

        self.settingsStore = settingsStore
        updater = UpdaterManager(
            automaticallyChecksForUpdates: persistedSettings.automaticallyChecksForUpdates,
            checksForUpdatesOnLaunch: persistedSettings.checksForUpdatesOnLaunch ?? false,
            settingsStore: settingsStore
        )

        clipDuration = Self.normalizedClipDuration(persistedSettings.clipDuration)
        startReplayBufferOnLaunch = true
        includeMicrophone = persistedSettings.includeMicrophone
        selectedMicrophoneID = persistedSettings.selectedMicrophoneID ?? ""
        captureSystemAudio = persistedSettings.captureSystemAudio
        systemAudioLevel = Self.resolvedSystemAudioLevel(
            persistedLevel: persistedSettings.systemAudioLevel,
            persistedMicrophoneLevel: persistedSettings.microphoneAudioLevel
        )
        microphoneAudioLevel = Self.normalizedMicrophoneAudioLevel(persistedSettings.microphoneAudioLevel ?? 1.0)
        showCursor = persistedSettings.showCursor
        enableGameNotifications = persistedSettings.enableGameNotifications
        captureResolutionPreset = persistedSettings.captureResolutionPreset
        videoQualityPreset = persistedSettings.videoQualityPreset
        appUUID = Self.resolvedAppUUID(persistedSettings.appUUID)
        websiteUserID = persistedSettings.websiteUserID ?? ""
        unlockedPaidFeatures = FeatureActivationManager.normalizedFeatures(persistedSettings.unlockedPaidFeatures)
        shortcutKey = persistedSettings.shortcutKey.isEmpty ? "9" : persistedSettings.shortcutKey
        useCommand = persistedSettings.useCommand
        useShift = persistedSettings.useShift
        useOption = persistedSettings.useOption
        useControl = persistedSettings.useControl
        saveDirectoryPath = persistedSettings.saveDirectoryPath.isEmpty ? defaultSaveDirectory : persistedSettings.saveDirectoryPath
        selectedCaptureDisplayID = persistedSettings.selectedCaptureDisplayID.isEmpty ? Self.defaultCaptureDisplayID() : persistedSettings.selectedCaptureDisplayID
        discordWebhookURLString = Self.lockedDiscordWebhookURL
        captureDeviceProfiles = persistedSettings.captureDeviceProfiles

        if let storedProfile = captureDeviceProfiles[selectedCaptureDisplayID] {
            applyCaptureDeviceProfile(storedProfile)
        }

        captureResolutionPreset = resolvedCaptureResolutionPreset(for: captureResolutionPreset)
        if captureResolutionPreset == .p2160 {
            videoQualityPreset = .highest
        }

        recorder.onUnexpectedStop = { [weak self] error in
            self?.handleUnexpectedRecorderStop(error)
        }
        recorder.onMicrophoneSampleBuffer = { [weak self] sampleBuffer in
            self?.voiceCommandManager.appendExternalAudioSampleBuffer(sampleBuffer)
        }

        voiceCommandManager.onClipCommand = { [weak self] command in
            Task { @MainActor in
                self?.handleVoiceClipCommand(command)
            }
        }
        voiceCommandManager.setPreferredMicrophoneDeviceID(resolvedSelectedMicrophoneDeviceID)

        log("AppModel initialized")
        savePreferences()
        reloadClips()
        refreshDiagnosticsLog()
        observeApplicationLifecycle()
        handlePendingIncomingFeatureActivationURLs()
        startAppInstallationRegistration()
        startEntitlementSyncLoop()
        requestNotificationAuthorizationIfNeeded()
    }

    var shortcutDisplayText: String {
        currentShortcut.displayString
    }

    var lastClipName: String? {
        lastClipURL?.lastPathComponent
    }

    var clipCountText: String {
        clips.isEmpty ? "No clips saved yet" : "\(clips.count) saved clip\(clips.count == 1 ? "" : "s")"
    }

    var hasDiscordWebhookConfigured: Bool {
        !discordWebhookURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var availableCaptureDisplays: [CaptureDisplayOption] {
        Self.captureDisplayOptions()
    }

    var availableMicrophones: [MicrophoneOption] {
        Self.microphoneOptions(selectedMicrophoneID: selectedMicrophoneID)
    }

    var selectedCaptureDisplaySummary: String {
        let displays = availableCaptureDisplays
        return displays.first(where: { $0.id == selectedCaptureDisplayID })?.title
            ?? displays.first?.title
            ?? "Current Display"
    }

    var selectedMicrophoneSummary: String {
        availableMicrophones.first(where: { $0.id == selectedMicrophoneID })?.title
            ?? (selectedMicrophoneID.isEmpty ? "System Default" : "Unavailable Microphone")
    }

    var microphoneStatusText: String {
        includeMicrophone ? "Microphone On" : "Microphone Off"
    }

    var systemAudioLevelPercent: Int {
        Int((systemAudioLevel * 100).rounded())
    }

    var microphoneAudioLevelPercent: Int {
        Int((microphoneAudioLevel * 100).rounded())
    }

    var systemAudioSettingsSubtitle: String {
        captureSystemAudio
            ? "Desktop and app sound will be captured at \(systemAudioLevelPercent)% volume."
            : "Desktop sound is muted from clips."
    }

    var systemAudioLevelSubtitle: String {
        captureSystemAudio
            ? "Lower this if your tutor, game, or desktop audio is overpowering your voice."
            : "Turn System Audio on to adjust its recorded volume."
    }

    var microphoneAudioLevelSubtitle: String {
        includeMicrophone
            ? "Raise this if your voice is quieter than the people or apps you are recording."
            : "Turn Microphone on to adjust how loud your voice sounds in saved clips."
    }

    var microphoneSelectionSubtitle: String {
        if selectedMicrophoneID.isEmpty {
            if let defaultMicrophone = Self.defaultMicrophoneDevice() {
                return "Using macOS default input: \(defaultMicrophone.localizedName)"
            }
            return "Using the macOS system default microphone"
        }

        if let selectedDevice = Self.microphoneDevice(withID: selectedMicrophoneID) {
            return "Using \(selectedDevice.localizedName) for clip audio and voice commands"
        }

        if let defaultMicrophone = Self.defaultMicrophoneDevice() {
            return "Saved microphone is unavailable. Falling back to \(defaultMicrophone.localizedName)"
        }

        return "Saved microphone is unavailable. MacClipper will fall back to the system default input."
    }

    var microphoneSettingsSubtitle: String {
        let inputDescription = selectedMicrophoneID.isEmpty ? "the system default input" : selectedMicrophoneSummary
        let voiceTriggerNote = shouldUseRecorderMicrophoneFeedForVoiceCommands
            ? " Voice trigger is sharing the same live capture mic instead of opening a second mic session."
            : ""

        if includeMicrophone {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .denied, .restricted:
                return "\(inputDescription) is selected, but macOS microphone access is blocked right now"
            case .notDetermined:
                return microphoneCaptureSuppressed
                    ? "Allow microphone access so \(inputDescription) can record your voice"
                    : "Ready on \(inputDescription).\(voiceTriggerNote)"
            case .authorized:
                return "Ready on \(inputDescription).\(voiceTriggerNote)"
            @unknown default:
                return "Ready on \(inputDescription).\(voiceTriggerNote)"
            }
        }

        return "Voice capture disabled"
    }

    var hasUnlocked4KPro: Bool {
        unlockedPaidFeatures.contains(PaidFeatureKey.fourKPro.rawValue)
    }

    var captureResolutionSelectionSummary: String {
        resolvedCaptureResolutionPreset(for: captureResolutionPreset).displayName
    }

    var appUUIDDisplayText: String {
        appUUID
    }

    var appUUIDShortDisplayText: String {
        String(appUUID.prefix(8)).uppercased()
    }

    var appUUIDSubtitle: String {
        "MacClipper creates this install UUID on first launch. Use it for bot grants, linking this Mac, and support when you need to identify this app install."
    }

    var websiteUserIDDisplayText: String {
        websiteUserID.isEmpty ? "Not Linked Yet" : websiteUserID
    }

    var websiteUserIDSubtitle: String {
        if websiteUserID.isEmpty {
            return "Sign in on the website, then buy or redeem features there to link this app to a website account."
        }

        return "Use this ID for website purchases, bot grants, and support when you need feature access synced back into MacClipper."
    }

    var captureResolutionSettingsSubtitle: String {
        if hasUnlocked4KPro {
            if captureResolutionPreset == .p2160 {
                return "Full 3840x2160 capture is enabled and locked to Highest quality."
            }

            return "4K Pro is unlocked. Switch to 4K whenever you want full-resolution clips."
        }

        return "720p through 1440p stay free. Buy 4K Pro once on the website and MacClipper will unlock it after the redirect."
    }

    var fourKProStatusText: String {
        if hasUnlocked4KPro {
            if websiteUserID.isEmpty {
                return "Purchased and active on this Mac."
            }

            return "Purchased on user \(websiteUserID)"
        }

        return "Locked. Buy it once on the website, then MacClipper will switch back with 4K ready."
    }

    var diagnosticsLogFilePath: String {
        AppLogger.shared.logFileURL.path
    }

    private var currentShortcut: Shortcut {
        Shortcut(
            key: shortcutKey,
            command: useCommand,
            shift: useShift,
            option: useOption,
            control: useControl
        )
    }

    private var resolvedSelectedMicrophoneDeviceID: String? {
        Self.resolvedMicrophoneDeviceID(from: selectedMicrophoneID)
    }

    private var shouldUseRecorderMicrophoneFeedForVoiceCommands: Bool {
        isRecording && includeMicrophone && !microphoneCaptureSuppressed
    }

    private var currentSettings: RecorderSettings {
        let resolvedResolutionPreset = resolvedCaptureResolutionPreset(for: captureResolutionPreset)
        return RecorderSettings(
            clipDuration: clipDuration,
            saveDirectory: URL(fileURLWithPath: saveDirectoryPath, isDirectory: true),
            includeMicrophone: includeMicrophone && !microphoneCaptureSuppressed,
            preferredMicrophoneDeviceID: resolvedSelectedMicrophoneDeviceID,
            captureSystemAudio: captureSystemAudio,
            systemAudioLevel: systemAudioLevel,
            microphoneAudioLevel: microphoneAudioLevel,
            showCursor: showCursor,
            preferredDisplayID: UInt32(selectedCaptureDisplayID),
            resolutionPreset: resolvedResolutionPreset,
            videoQuality: effectiveVideoQualityPreset(for: videoQualityPreset, resolutionPreset: resolvedResolutionPreset)
        )
    }

    func captureResolutionOptionTitle(for preset: CaptureResolutionPreset) -> String {
        guard preset.requires4KProUnlock, !hasUnlocked4KPro else {
            return preset.displayName
        }

        return "\(preset.displayName) Buy"
    }

    func savePreferences() {
        clipDuration = Self.normalizedClipDuration(clipDuration)
        startReplayBufferOnLaunch = true
        shortcutKey = String((shortcutKey.isEmpty ? "9" : shortcutKey.prefix(1))).uppercased()
        appUUID = Self.resolvedAppUUID(appUUID)
        websiteUserID = FeatureActivationManager.normalizedUserID(websiteUserID)
        unlockedPaidFeatures = FeatureActivationManager.normalizedFeatures(unlockedPaidFeatures)
        captureResolutionPreset = resolvedCaptureResolutionPreset(for: captureResolutionPreset)
        videoQualityPreset = effectiveVideoQualityPreset(for: videoQualityPreset, resolutionPreset: captureResolutionPreset)
        systemAudioLevel = Self.normalizedSystemAudioLevel(systemAudioLevel)
        microphoneAudioLevel = Self.normalizedMicrophoneAudioLevel(microphoneAudioLevel)

        defaults.set(clipDuration, forKey: "clipDuration")
        defaults.set(startReplayBufferOnLaunch, forKey: "startReplayBufferOnLaunch")
        defaults.set(includeMicrophone, forKey: "includeMicrophone")
        defaults.set(selectedMicrophoneID, forKey: "selectedMicrophoneID")
        defaults.set(captureSystemAudio, forKey: "captureSystemAudio")
        defaults.set(systemAudioLevel, forKey: "systemAudioLevel")
        defaults.set(microphoneAudioLevel, forKey: "microphoneAudioLevel")
        defaults.set(showCursor, forKey: "showCursor")
        defaults.set(enableGameNotifications, forKey: "enableGameNotifications")
        defaults.set(captureResolutionPreset.rawValue, forKey: "captureResolutionPreset")
        defaults.set(videoQualityPreset.rawValue, forKey: "videoQualityPreset")
        defaults.set(appUUID, forKey: "appUUID")
        defaults.set(websiteUserID, forKey: "websiteUserID")
        defaults.set(unlockedPaidFeatures, forKey: "unlockedPaidFeatures")
        defaults.set(shortcutKey, forKey: "shortcutKey")
        defaults.set(useCommand, forKey: "useCommand")
        defaults.set(useShift, forKey: "useShift")
        defaults.set(useOption, forKey: "useOption")
        defaults.set(useControl, forKey: "useControl")
        defaults.set(saveDirectoryPath, forKey: "saveDirectoryPath")
        defaults.set(selectedCaptureDisplayID, forKey: "selectedCaptureDisplayID")
        discordWebhookURLString = Self.lockedDiscordWebhookURL
        defaults.set(Self.lockedDiscordWebhookURL, forKey: "discordWebhookURLString")
        persistCaptureDeviceProfile(for: selectedCaptureDisplayID)
        persistSettingsSnapshot()

        hotkeyManager.register(shortcut: currentShortcut) { [weak self] in
            Task { @MainActor in
                self?.saveClip()
            }
        }
        voiceCommandManager.setPreferredMicrophoneDeviceID(resolvedSelectedMicrophoneDeviceID)
        refreshVoiceCommandListenerState()
        recorder.update(settings: currentSettings)
    }

    func setVideoQualityPreset(_ preset: VideoQualityPreset) {
        if captureResolutionPreset == .p2160 && preset != .highest {
            if videoQualityPreset != .highest {
                videoQualityPreset = .highest
                savePreferences()
            }
            statusText = "4K Pro stays on Highest quality for full-detail capture."
            return
        }

        guard videoQualityPreset != preset else { return }
        videoQualityPreset = preset
        savePreferences()
    }

    func setCaptureResolutionPreset(_ preset: CaptureResolutionPreset) {
        if preset.requires4KProUnlock && !hasUnlocked4KPro {
            statusText = "4K Pro opens on the website purchase page. Buy it once and MacClipper will unlock it on the way back."
            open4KPurchasePage()
            return
        }

        let resolvedPreset = resolvedCaptureResolutionPreset(for: preset)
        let resolvedQuality = effectiveVideoQualityPreset(for: videoQualityPreset, resolutionPreset: resolvedPreset)
        let didChangeResolution = captureResolutionPreset != resolvedPreset
        let didChangeQuality = videoQualityPreset != resolvedQuality

        guard didChangeResolution || didChangeQuality else { return }

        captureResolutionPreset = resolvedPreset
        videoQualityPreset = resolvedQuality
        if resolvedPreset == .p2160 {
            statusText = "4K Pro is enabled at Highest quality."
        }
        savePreferences()
    }

    func setSelectedCaptureDisplayID(_ displayID: String) {
        guard selectedCaptureDisplayID != displayID else { return }
        persistCaptureDeviceProfile(for: selectedCaptureDisplayID)
        selectedCaptureDisplayID = displayID
        if let storedProfile = captureDeviceProfiles[displayID] {
            applyCaptureDeviceProfile(storedProfile)
        }
        savePreferences()

        guard isRecording, !isBusy else { return }
        restartRecording(status: "Switching capture to \(selectedCaptureDisplaySummary)…")
    }

    func setSelectedMicrophoneID(_ microphoneID: String) {
        guard selectedMicrophoneID != microphoneID else { return }

        selectedMicrophoneID = microphoneID
        let microphoneLogID = microphoneID.isEmpty ? "system-default" : microphoneID
        log("microphone input changed id=\(microphoneLogID)")
        savePreferences()

        guard includeMicrophone, isRecording, !isBusy else { return }
        restartRecording(status: "Switching microphone input…")
    }

    func open4KPurchasePage() {
        guard let purchaseURL = Self.purchasePortalURL() else {
            statusText = "MacClipper could not build the website purchase URL."
            return
        }

        guard var components = URLComponents(url: purchaseURL, resolvingAgainstBaseURL: false) else {
            NSWorkspace.shared.open(purchaseURL)
            return
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "appUuid" }
        queryItems.append(URLQueryItem(name: "appUuid", value: appUUID))
        components.queryItems = queryItems

        NSWorkspace.shared.open(components.url ?? purchaseURL)
    }

    func copyAppUUID() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appUUID, forType: .string)
        statusText = "Copied app UUID."
    }

    func copyWebsiteUserID() {
        guard !websiteUserID.isEmpty else {
            statusText = "Buy or redeem a website feature first so MacClipper can link a user ID here."
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(websiteUserID, forType: .string)
        statusText = "Copied website user ID."
    }

    func reloadClips() {
        let folderURL = URL(fileURLWithPath: saveDirectoryPath, isDirectory: true)
        let preferredLastClipURL = lastClipURL
        let preferredSelectedClipURL = selectedClip?.url

        reloadClipsTask?.cancel()
        reloadClipsTask = Task.detached(priority: .utility) { [weak self, folderURL, preferredLastClipURL, preferredSelectedClipURL] in
            try? ClipStorageManager.ensureRootDirectory(at: folderURL)
            let loadedClips = ClipLibraryLoader.loadSavedClips(from: folderURL)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.saveDirectoryPath == folderURL.path else { return }
                self.applyLoadedClips(
                    loadedClips,
                    preferredLastClipURL: preferredLastClipURL,
                    preferredSelectedClipURL: preferredSelectedClipURL
                )
            }
        }
    }

    private func observeApplicationLifecycle() {
        let center = NotificationCenter.default

        notificationObservers = [
            center.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshVoiceCommandListenerState()
                    self?.scheduleAutomaticRecordingStartIfNeeded(after: 0.75)
                }
            },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshVoiceCommandListenerState()
                    self?.ensureRecordingActive(reason: "Keeping capture live…")
                    self?.retryAutomaticRecordingStartIfNeeded()
                }
            },
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.savePreferences()
                }
            },
            center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.voiceCommandManager.stop()
                    self?.entitlementSyncTask?.cancel()
                    self?.savePreferences()
                }
            },
            center.addObserver(forName: AppDelegate.deepLinkNotification, object: nil, queue: .main) { [weak self] notification in
                guard let urls = notification.userInfo?[AppDelegate.deepLinkUserInfoKey] as? [URL] else { return }
                Task { @MainActor in
                    self?.handleIncomingFeatureActivationURLs(urls)
                }
            }
        ]

        refreshVoiceCommandListenerState()
        scheduleAutomaticRecordingStartIfNeeded(after: 0.75)
    }

    private func scheduleAutomaticRecordingStartIfNeeded(after delay: TimeInterval) {
        guard startReplayBufferOnLaunch, !didAttemptInitialRecording else { return }
        didAttemptInitialRecording = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard self.startReplayBufferOnLaunch, !self.isRecording, !self.isBusy else { return }
            self.startRecording()
        }
    }

    private func retryAutomaticRecordingStartIfNeeded() {
        guard shouldRetryAutomaticStart, startReplayBufferOnLaunch, !isRecording, !isBusy else { return }
        shouldRetryAutomaticStart = false
        startRecording()
    }

    func ensureRecordingActive(reason: String = "Keeping capture live…") {
        guard startReplayBufferOnLaunch, !isRecording, !isBusy else { return }
        restartRecording(status: reason)
    }

    @discardableResult
    private func handleRecordingStartError(_ error: Error) -> Bool {
        switch error {
        case RecorderError.screenPermissionDenied:
            shouldRetryAutomaticStart = startReplayBufferOnLaunch
            statusText = "Allow Screen Recording in System Settings, then return to MacClipper."
            return false
        case RecorderError.microphonePermissionDenied:
            if includeMicrophone && !microphoneCaptureSuppressed {
                microphoneCaptureSuppressed = true
                refreshVoiceCommandListenerState()
                shouldRetryAutomaticStart = false
                statusText = "Microphone access was denied, so capture is retrying without microphone audio. Your saved microphone setting stays on."
                return true
            }

            shouldRetryAutomaticStart = false
            statusText = "Allow Microphone access in System Settings, then return to MacClipper."
            return false
        default:
            shouldRetryAutomaticStart = startReplayBufferOnLaunch
            statusText = error.localizedDescription
            scheduleAutomaticRearm(after: 2.5, preservingBuffer: isRecoveringRecorder, status: "Retrying capture…")
            return false
        }
    }

    func toggleRecording() {
        guard !isBusy else { return }

        if !isRecording {
            startRecording()
            return
        }

        statusText = "Capture stays on while MacClipper is open."
    }

    func setStartReplayBufferOnLaunch(_ enabled: Bool) {
        startReplayBufferOnLaunch = true
        savePreferences()

        guard !isBusy else { return }

        if !isRecording {
            startRecording()
        }
    }

    func startRecording() {
        guard !isBusy, !isRecording else { return }
        refreshMicrophoneCaptureSuppression()
        log("startRecording requested")
        armRecording(status: "Starting capture…", preservingBuffer: false)
    }

    private func restartRecording(status: String) {
        guard !isBusy else { return }
        refreshMicrophoneCaptureSuppression()
        log("restartRecording requested status=\(status)")
        armRecording(status: status, preservingBuffer: false)
    }

    private func recoverRecording(status: String) {
        guard !isBusy, !isRecording else { return }
        refreshMicrophoneCaptureSuppression()
        log("recoverRecording requested status=\(status)")
        armRecording(status: status, preservingBuffer: true)
    }

    private func armRecording(status: String, preservingBuffer: Bool) {
        automaticRearmTask?.cancel()
        isBusy = true
        statusText = status

        Task {
            let shouldRetryImmediately: Bool

            do {
                try await recorder.start(with: currentSettings, preservingBuffer: preservingBuffer)
                shouldRetryAutomaticStart = false
                isRecoveringRecorder = false
                statusText = preservingBuffer
                    ? "Capture recovered on \(selectedCaptureDisplaySummary)"
                    : "Capture is live on \(selectedCaptureDisplaySummary)"
                log("recorder armed preservingBuffer=\(preservingBuffer) display=\(selectedCaptureDisplaySummary)")
                isRecording = true
                refreshVoiceCommandListenerState()
                shouldRetryImmediately = false
            } catch {
                shouldRetryImmediately = handleRecordingStartError(error)
                if !shouldRetryImmediately {
                    isRecoveringRecorder = false
                }
                log("recorder start failed message=\(error.localizedDescription)")
                isRecording = false
                refreshVoiceCommandListenerState()
            }
            isBusy = false

            if shouldRetryImmediately {
                startRecording()
            } else if isRecording, !pendingClipRequests.isEmpty {
                processNextQueuedClipIfNeeded()
            }
        }
    }

    func stopRecording() {
        log("stopRecording ignored because capture is always on")
        statusText = "Capture stays on while MacClipper is open."
    }

    func saveClip() {
        guard isRecording else {
            log("saveClip ignored because recorder is not active")
            return
        }
        guard !isBusy || isProcessingClipQueue else {
            log("saveClip ignored because recorder is busy without an active clip queue")
            return
        }

        let request = PendingClipRequest(
            capturePoint: recorder.makeCapturePoint(),
            duration: Int(clipDuration),
            sourceApp: captureSourceAppSnapshot(),
            suppressMicrophoneInExport: false
        )

        let sourceName = request.sourceApp?.name ?? CaptureSourceAppDetector.desktopSourceApp.name
        log("clip queued duration=\(request.duration) source=\(sourceName)")

        pendingClipRequests.append(request)
        let queuedClipCount = pendingClipRequests.count + (isProcessingClipQueue ? 1 : 0)

        if queuedClipCount > 1 {
            statusText = "Clipping \(queuedClipCount) clips…"
            postQueuedClipNotification(totalCount: queuedClipCount, sourceApp: request.sourceApp)
        } else {
            statusText = clipProgressText(for: request)
            postClipStartedNotification(sourceApp: request.sourceApp, duration: request.duration)
        }

        processNextQueuedClipIfNeeded()
    }

    private func handleVoiceClipCommand(_ command: String) {
        log("voice clip command received command=\(command)")

        guard isRecording else {
            ensureRecordingActive(reason: "Voice command heard. Re-arming capture…")
            statusText = "Heard \"Mac clip that\", but capture is not live yet."
            return
        }

        saveClip()
    }

    private func processNextQueuedClipIfNeeded() {
        guard isRecording, !isProcessingClipQueue, !pendingClipRequests.isEmpty else { return }

        isProcessingClipQueue = true
        isBusy = true
        let request = pendingClipRequests.removeFirst()
        activeClipRequest = request
        log("processing clip request duration=\(request.duration) source=\(request.sourceApp?.name ?? CaptureSourceAppDetector.desktopSourceApp.name)")

        if !pendingClipRequests.isEmpty {
            statusText = "Clipping \(pendingClipRequests.count + 1) clips…"
        } else {
            statusText = clipProgressText(for: request)
        }

        Task {
            do {
                let clipURL = try await recorder.saveReplayClip(
                    capturePoint: request.capturePoint,
                    suppressMicrophoneInExport: request.suppressMicrophoneInExport
                )
                persistMetadata(for: clipURL, sourceApp: request.sourceApp, capturedAt: request.capturePoint.requestedAt)
                lastClipURL = clipURL
                insertSavedClipIntoLibrary(clipURL, sourceApp: request.sourceApp, capturedAt: request.capturePoint.requestedAt)
                postClipSavedNotification(for: clipURL, sourceApp: request.sourceApp, duration: request.duration)
                log("clip saved output=\(clipURL.lastPathComponent)")
                let remainingCount = pendingClipRequests.count
                statusText = remainingCount > 0
                    ? "Saved \(clipURL.lastPathComponent) • \(remainingCount) more queued"
                    : "Saved \(clipURL.lastPathComponent)"
            } catch let recorderError as RecorderError {
                if !isRecoveringRecorder {
                    statusText = recorderError.localizedDescription
                    log("clip failed recorderError=\(recorderError.localizedDescription)")
                    switch recorderError {
                    case .bufferNotReady, .noBufferedClip:
                        break
                    default:
                        postClipFailedNotification(
                            sourceApp: request.sourceApp,
                            title: request.sourceApp.map { "\($0.name) clip failed" } ?? "Clip failed",
                            message: recorderError.localizedDescription
                        )
                    }
                }
            } catch {
                if !isRecoveringRecorder {
                    statusText = error.localizedDescription
                    log("clip failed error=\(error.localizedDescription)")
                    postClipFailedNotification(
                        sourceApp: request.sourceApp,
                        title: request.sourceApp.map { "\($0.name) clip failed" } ?? "Clip failed",
                        message: error.localizedDescription
                    )
                }
            }

            if activeClipRequest?.id == request.id {
                activeClipRequest = nil
            }

            isProcessingClipQueue = false
            if pendingClipRequests.isEmpty {
                isBusy = false
            } else {
                processNextQueuedClipIfNeeded()
            }
        }
    }

    func openClipsFolder() {
        let url = URL(fileURLWithPath: saveDirectoryPath, isDirectory: true)
        try? ClipStorageManager.ensureRootDirectory(at: url)
        NSWorkspace.shared.open(url)
    }

    func openClip(_ clip: SavedClip) {
        NSWorkspace.shared.open(clip.url)
    }

    func revealClip(at clipURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([clipURL])
    }

    func deleteClip(_ clip: SavedClip) {
        let fileManager = FileManager.default
        let metadataURL = ClipLibraryLoader.metadataURL(for: clip.url)

        do {
            if fileManager.fileExists(atPath: metadataURL.path) {
                try? fileManager.removeItem(at: metadataURL)
            }

            var trashedURL: NSURL?
            if fileManager.fileExists(atPath: clip.url.path) {
                try fileManager.trashItem(at: clip.url, resultingItemURL: &trashedURL)
            }

            clips.removeAll { $0.url == clip.url }
            if lastClipURL == clip.url {
                lastClipURL = clips.first?.url
            }

            if selectedClip?.url == clip.url {
                selectedClip = clips.first
            }

            statusText = "Deleted \(clip.url.lastPathComponent)"
            log("clip deleted file=\(clip.url.lastPathComponent)")
        } catch {
            statusText = "Could not delete \(clip.url.lastPathComponent)"
            log("clip delete failed file=\(clip.url.lastPathComponent) message=\(error.localizedDescription)")
        }
    }

    func testDiscordWebhook() {
        let webhookURL = discordWebhookURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !webhookURL.isEmpty else {
            postClipFailedNotification(
                sourceApp: nil,
                title: "Discord not connected",
                message: "Paste a Discord channel webhook in Settings before testing the connection."
            )
            return
        }

        statusText = "Testing Discord channel…"

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await self.discordWebhookManager.testWebhook(webhookURLString: webhookURL)
                self.statusText = "Discord channel is connected"
                self.postDiscordConnectionSuccessNotification()
            } catch {
                self.statusText = error.localizedDescription
                self.postClipFailedNotification(
                    sourceApp: nil,
                    title: "Discord test failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    func showDiscordWebhookSetupGuide() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "How To Connect Discord"
        alert.informativeText = "1. Open Discord.\n2. Open your server settings.\n3. Go to Integrations > Webhooks.\n4. Create a webhook for the channel you want clips sent to.\n5. Copy the webhook URL.\n6. Paste it into MacClipper Settings under Discord.\n7. Click Test Channel."
        alert.addButton(withTitle: "Open Discord")
        alert.addButton(withTitle: "Close")

        NSApplication.shared.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "https://discord.com/channels/@me") {
            NSWorkspace.shared.open(url)
        }
    }

    func pickSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Clips Folder"

        if panel.runModal() == .OK, let url = panel.url {
            saveDirectoryPath = url.path
            log("save directory changed path=\(url.path)")
            savePreferences()
            reloadClips()
        }
    }

    func refreshDiagnosticsLog() {
        diagnosticsLogText = AppLogger.shared.readLog()
        diagnosticsLogStatusText = "Loaded log at \(Self.logTimestampString(from: Date()))"
    }

    func copyDiagnosticsLog() {
        let logText = AppLogger.shared.readLog()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logText, forType: .string)
        diagnosticsLogText = logText
        diagnosticsLogStatusText = "Copied diagnostics log at \(Self.logTimestampString(from: Date()))"
    }

    func clearDiagnosticsLog() {
        AppLogger.shared.clearLog()
        diagnosticsLogText = AppLogger.shared.readLog()
        diagnosticsLogStatusText = "Cleared diagnostics log at \(Self.logTimestampString(from: Date()))"
    }

    func revealDiagnosticsLog() {
        let logURL = AppLogger.shared.logFileURL
        if FileManager.default.fileExists(atPath: logURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([logURL])
        } else {
            NSWorkspace.shared.open(logURL.deletingLastPathComponent())
        }
    }

    private func captureSourceAppSnapshot() -> ClipSourceApp? {
        CaptureSourceAppDetector.captureCurrentSourceApp(bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    private static func defaultCaptureDisplayID() -> String {
        if let mainScreen = NSScreen.main,
           let screenNumber = mainScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return String(screenNumber.uint32Value)
        }

        if let firstScreen = NSScreen.screens.first,
           let screenNumber = firstScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return String(screenNumber.uint32Value)
        }

        return "0"
    }

    private static func captureDisplayOptions() -> [CaptureDisplayOption] {
        NSScreen.screens.compactMap { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }

            let displayID = screenNumber.uint32Value
            let titleSuffix = screen == NSScreen.main ? " (Main)" : ""
            let width = Int(screen.frame.width.rounded())
            let height = Int(screen.frame.height.rounded())

            return CaptureDisplayOption(
                id: String(displayID),
                title: "\(screen.localizedName)\(titleSuffix)",
                detail: "\(width)x\(height)"
            )
        }
    }

    private static func audioCaptureDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified).devices
            .sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
    }

    private static func defaultMicrophoneDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(for: .audio) ?? audioCaptureDevices().first
    }

    private static func microphoneDevice(withID deviceID: String) -> AVCaptureDevice? {
        guard !deviceID.isEmpty else { return defaultMicrophoneDevice() }
        return audioCaptureDevices().first(where: { $0.uniqueID == deviceID })
    }

    private static func resolvedMicrophoneDeviceID(from deviceID: String) -> String? {
        guard !deviceID.isEmpty else { return nil }
        return microphoneDevice(withID: deviceID)?.uniqueID
    }

    private static func microphoneOptions(selectedMicrophoneID: String) -> [MicrophoneOption] {
        let devices = audioCaptureDevices()
        let defaultDetail = defaultMicrophoneDevice()?.localizedName ?? "Follow macOS input"
        var options = [
            MicrophoneOption(id: "", title: "System Default", detail: defaultDetail)
        ]

        options.append(contentsOf: devices.map { device in
            MicrophoneOption(id: device.uniqueID, title: device.localizedName, detail: "")
        })

        if !selectedMicrophoneID.isEmpty && !options.contains(where: { $0.id == selectedMicrophoneID }) {
            options.append(
                MicrophoneOption(
                    id: selectedMicrophoneID,
                    title: "Unavailable Microphone",
                    detail: "Reconnect it or choose another input"
                )
            )
        }

        return options
    }

    private func resolvedCaptureResolutionPreset(for preset: CaptureResolutionPreset) -> CaptureResolutionPreset {
        guard preset.requires4KProUnlock, !hasUnlocked4KPro else {
            return preset
        }

        return .highestFreePreset
    }

    private func effectiveVideoQualityPreset(for preset: VideoQualityPreset, resolutionPreset: CaptureResolutionPreset) -> VideoQualityPreset {
        resolutionPreset == .p2160 ? .highest : preset
    }

    @discardableResult
    private func enforce4KProResolutionAccess(showStatus: Bool) -> Bool {
        let resolvedPreset = resolvedCaptureResolutionPreset(for: captureResolutionPreset)
        guard resolvedPreset != captureResolutionPreset else { return false }

        captureResolutionPreset = resolvedPreset
        if showStatus {
            statusText = "4K Pro is not active on this Mac yet, so capture dropped back to \(resolvedPreset.displayName)."
        }
        return true
    }

    private func handlePendingIncomingFeatureActivationURLs() {
        handleIncomingFeatureActivationURLs(AppDelegate.takePendingIncomingURLs())
    }

    private func handleIncomingFeatureActivationURLs(_ urls: [URL]) {
        urls.forEach(handleIncomingFeatureActivationURL)
    }

    private func handleIncomingFeatureActivationURL(_ url: URL) {
        guard url.scheme?.lowercased() == "macclipper" else { return }

        let normalizedHost = (url.host ?? "").lowercased()
        let normalizedPath = url.path.lowercased()
        let isFeatureGrantURL = normalizedHost == "feature-grant"
            || normalizedHost == "purchase-complete"
            || normalizedPath == "/feature-grant"
            || normalizedPath == "/purchase-complete"

        guard isFeatureGrantURL,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let userID = queryItems.first(where: { $0.name == "userId" })?.value,
              let feature = queryItems.first(where: { $0.name == "feature" })?.value,
              let token = queryItems.first(where: { $0.name == "token" })?.value else {
            return
        }

        let normalizedUserID = FeatureActivationManager.normalizedUserID(userID)
        let normalizedFeature = FeatureActivationManager.normalizedFeature(feature)

        guard FeatureActivationManager.isValidActivationToken(userID: normalizedUserID, feature: normalizedFeature, token: token) else {
            statusText = "MacClipper rejected that feature unlock link."
            return
        }

        applyActivatedFeature(normalizedFeature, for: normalizedUserID)
    }

    private func applyActivatedFeature(_ feature: String, for userID: String) {
        let wasAlreadyUnlocked = unlockedPaidFeatures.contains(feature)

        websiteUserID = userID
        unlockedPaidFeatures = FeatureActivationManager.normalizedFeatures(unlockedPaidFeatures + [feature])

        if feature == PaidFeatureKey.fourKPro.rawValue {
            captureResolutionPreset = .p2160
            videoQualityPreset = .highest
            statusText = wasAlreadyUnlocked
                ? "4K Pro is already active for user \(userID)."
                : "4K Pro unlocked. Capture switched to 4K Highest quality."
        } else {
            statusText = wasAlreadyUnlocked
                ? "\(FeatureActivationManager.featureDisplayName(feature)) is already active for user \(userID)."
                : "\(FeatureActivationManager.featureDisplayName(feature)) unlocked for user \(userID)."
        }

        savePreferences()
        celebrateActivatedFeature(feature, userID: userID, isNewUnlock: !wasAlreadyUnlocked)
    }

    private func startEntitlementSyncLoop() {
        entitlementSyncTask?.cancel()
        entitlementSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await self.syncEntitlementsFromWebsiteIfNeeded()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func startAppInstallationRegistration() {
        appInstallationRegistrationTask?.cancel()
        appInstallationRegistrationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.registerAppInstallationWithAccountServiceIfNeeded()
            await self.syncEntitlementsFromWebsiteIfNeeded()
        }
    }

    private func registerAppInstallationWithAccountServiceIfNeeded() async {
        guard let serviceBaseURL = Self.accountServiceBaseURL(),
              let machineIdentity = MachineIdentityProvider.current() else {
            return
        }

        let requestURL = serviceBaseURL.appendingPathComponent("api/app-installations/resolve")
        let payload = AppInstallationRegistrationPayload(
            appUuid: Self.resolvedAppUUID(appUUID),
            machineIdentifier: machineIdentity.identifier,
            machineName: machineIdentity.name,
            machineModel: machineIdentity.modelIdentifier,
            systemVersion: machineIdentity.systemVersion,
            appVersion: Self.appShortVersionString(),
            buildVersion: Self.appBuildVersionString()
        )

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode) else {
                return
            }

            let snapshot = try JSONDecoder().decode(AppInstallationRegistrationSnapshot.self, from: data)
            let resolvedAppUUID = Self.resolvedAppUUID(snapshot.installation.appUuid)
            let resolvedWebsiteUserID = FeatureActivationManager.normalizedUserID(snapshot.installation.websiteUserID)
            let didChangeAppUUID = resolvedAppUUID != appUUID
            let shouldAdoptWebsiteUserID = websiteUserID.isEmpty && !resolvedWebsiteUserID.isEmpty

            guard didChangeAppUUID || shouldAdoptWebsiteUserID else {
                return
            }

            appUUID = resolvedAppUUID
            if shouldAdoptWebsiteUserID {
                websiteUserID = resolvedWebsiteUserID
            }
            savePreferences()
            log("resolved app identity from account service appUuid=\(resolvedAppUUID)")
        } catch {
            log("failed to register app installation with account service: \(error.localizedDescription)")
        }
    }

    private func syncEntitlementsFromWebsiteIfNeeded() async {
        let normalizedUserID = FeatureActivationManager.normalizedUserID(websiteUserID)
        let resolvedAppUUID = Self.resolvedAppUUID(appUUID)
        guard !normalizedUserID.isEmpty || !resolvedAppUUID.isEmpty,
              let serviceBaseURL = Self.accountServiceBaseURL() else {
            return
        }

        var components = URLComponents(url: serviceBaseURL.appendingPathComponent("api/entitlements/by-user-id"), resolvingAgainstBaseURL: false)
        if !normalizedUserID.isEmpty {
            components?.queryItems = [URLQueryItem(name: "userId", value: normalizedUserID)]
        } else {
            components?.queryItems = [URLQueryItem(name: "appUuid", value: resolvedAppUUID)]
        }

        guard let url = components?.url else {
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return
            }

            let payload = try JSONDecoder().decode(WebsiteEntitlementSnapshot.self, from: data)
            applyEntitlementSnapshot(payload.user)
        } catch {
            return
        }
    }

    private func applyEntitlementSnapshot(_ user: WebsiteEntitlementUser) {
        let normalizedUserID = FeatureActivationManager.normalizedUserID(user.id)
        let normalizedFeatures = FeatureActivationManager.normalizedFeatures(
            user.accountStatus == "active" ? user.paidFeatures : []
        )
        let previousFeatures = Set(unlockedPaidFeatures)
        let currentFeatures = Set(normalizedFeatures)
        let addedFeatures = currentFeatures.subtracting(previousFeatures)
        let removedFeatures = previousFeatures.subtracting(currentFeatures)

        websiteUserID = normalizedUserID
        unlockedPaidFeatures = normalizedFeatures

        if removedFeatures.contains(PaidFeatureKey.fourKPro.rawValue) {
            let didDowngradeResolution = enforce4KProResolutionAccess(showStatus: false)
            if didDowngradeResolution {
                statusText = "4K Pro was removed for this user, so capture dropped back to \(captureResolutionPreset.displayName)."
            }
        }

        if addedFeatures.contains(PaidFeatureKey.fourKPro.rawValue) {
            captureResolutionPreset = .p2160
            videoQualityPreset = .highest
            statusText = "4K Pro synced live for user \(normalizedUserID)."
        }

        guard !addedFeatures.isEmpty || !removedFeatures.isEmpty else { return }

        savePreferences()

        for feature in addedFeatures.sorted() {
            celebrateActivatedFeature(feature, userID: normalizedUserID, isNewUnlock: false)
        }
    }

    private func celebrateActivatedFeature(_ feature: String, userID: String, isNewUnlock: Bool) {
        let featureTitle = FeatureActivationManager.featureDisplayName(feature)
        NSApplication.shared.activate(ignoringOtherApps: true)
        GameNotificationManager.shared.show(
            title: isNewUnlock ? "\(featureTitle) unlocked" : "\(featureTitle) synced",
            message: "User \(userID) can use \(featureTitle) now.",
            sourceApp: nil
        )
    }

    private static func purchasePortalURL() -> URL? {
        let configuredURL = ((Bundle.main.object(forInfoDictionaryKey: "MacClipperAccountPortalURL") as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedURLString = configuredURL.isEmpty ? defaultPurchasePortalURLString : configuredURL
        return URL(string: resolvedURLString)
    }

    private static func accountServiceBaseURL() -> URL? {
        guard let purchasePortalURL = purchasePortalURL(),
              let scheme = purchasePortalURL.scheme,
              let host = purchasePortalURL.host else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = purchasePortalURL.port
        return components.url
    }

    private static func appShortVersionString() -> String {
        ((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appBuildVersionString() -> String {
        ((Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleUnexpectedRecorderStop(_ error: Error) {
        if let activeClipRequest {
            pendingClipRequests.insert(activeClipRequest, at: 0)
            self.activeClipRequest = nil
        }

        isRecording = false
        isBusy = false
        isProcessingClipQueue = false
        isRecoveringRecorder = true
        shouldRetryAutomaticStart = true
        refreshVoiceCommandListenerState()
        statusText = "Capture interrupted. Reconnecting desktop capture…"
        log("unexpected recorder stop message=\(error.localizedDescription)")

        guard startReplayBufferOnLaunch else { return }

        scheduleAutomaticRearm(after: 0.75, preservingBuffer: true, status: "Reconnecting capture…")

        NSLog("MacClipper capture interrupted: \(error.localizedDescription)")
    }

    private func scheduleAutomaticRearm(after delay: TimeInterval, preservingBuffer: Bool, status: String) {
        automaticRearmTask?.cancel()

        guard startReplayBufferOnLaunch else { return }

        automaticRearmTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard !Task.isCancelled else { return }
            guard self.startReplayBufferOnLaunch, !self.isRecording, !self.isBusy else { return }

            if preservingBuffer {
                self.recoverRecording(status: status)
            } else {
                self.restartRecording(status: status)
            }
        }
    }

    private func persistMetadata(for clipURL: URL, sourceApp: ClipSourceApp?, capturedAt: Date = Date()) {
        let metadata = ClipMetadata(sourceApp: sourceApp, capturedAt: capturedAt)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(metadata)
            try data.write(to: ClipLibraryLoader.metadataURL(for: clipURL), options: .atomic)
        } catch {
            NSLog("MacClipper metadata write failed: \(error.localizedDescription)")
        }
    }

    private func requestNotificationAuthorizationIfNeeded() {
        guard !enableGameNotifications else { return }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                NSLog("MacClipper notification authorization error: \(error.localizedDescription)")
            }
        }
    }

    private func postClipStartedNotification(sourceApp: ClipSourceApp?, duration: Int) {
        guard enableGameNotifications else { return }

        let gameName = sourceApp?.name ?? CaptureSourceAppDetector.desktopSourceApp.name
        let message = sourceApp?.isDesktopCapture == true
            ? "Trimming the last \(duration) seconds from desktop capture…"
            : "Saving the last \(duration) seconds…"
        GameNotificationManager.shared.show(
            title: "\(gameName) clipping now",
            message: message,
            sourceApp: sourceApp
        )
    }

    private func clipProgressText(for request: PendingClipRequest) -> String {
        if let sourceApp = request.sourceApp {
            if sourceApp.isDesktopCapture {
                return "Desktop trimming \(request.duration) seconds…"
            }
            return "Clipping \(sourceApp.name) • last \(request.duration) seconds…"
        }

        return "Desktop trimming \(request.duration) seconds…"
    }

    private func postQueuedClipNotification(totalCount: Int, sourceApp: ClipSourceApp?) {
        guard enableGameNotifications, totalCount > 1 else { return }

        GameNotificationManager.shared.show(
            title: "Clipping \(totalCount) clips",
            message: "MacClipper queued your shortcuts and is saving them one by one.",
            sourceApp: sourceApp
        )
    }

    private func postClipSavedNotification(for clipURL: URL, sourceApp: ClipSourceApp?, duration: Int) {
        let title: String
        if let sourceApp {
            title = sourceApp.isDesktopCapture ? "Desktop clip saved" : "\(sourceApp.name) clip saved"
        } else {
            title = "Clip saved"
        }
        let message = "Finished and saved in \(clipURL.deletingLastPathComponent().path)"

        if enableGameNotifications {
            GameNotificationManager.shared.show(
                title: title,
                message: message,
                sourceApp: sourceApp,
                previewURL: clipURL,
                actions: clipSavedActions(for: clipURL, sourceApp: sourceApp)
            )
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = "Last \(duration) seconds captured and in your folder"
        content.body = clipURL.lastPathComponent
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "clip-saved-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("MacClipper notification delivery error: \(error.localizedDescription)")
            }
        }
    }

    private func clipSavedActions(for clipURL: URL, sourceApp: ClipSourceApp?) -> [GameNotificationAction] {
        var actions: [GameNotificationAction] = [
            GameNotificationAction(title: "Share", systemImage: "square.and.arrow.up", tint: MacClipperTheme.cyan) { [weak self] in
                self?.presentSharePanel(for: clipURL, sourceApp: sourceApp)
            },
            GameNotificationAction(title: "Reveal", systemImage: "folder.fill", tint: MacClipperTheme.ember) { [weak self] in
                self?.revealClip(at: clipURL)
            }
        ]

        if hasDiscordWebhookConfigured {
            actions.append(
                GameNotificationAction(title: "Discord", systemImage: "paperplane.fill", tint: MacClipperTheme.cyan) { [weak self] in
                    self?.uploadClipToDiscord(clipURL, sourceApp: sourceApp)
                }
            )
        }

        return actions
    }

    private func presentSharePanel(for clipURL: URL, sourceApp: ClipSourceApp?) {
        ClipSharePanelManager.shared.show(
            clipURL: clipURL,
            discordConnected: hasDiscordWebhookConfigured,
            onDiscordChannel: { [weak self] in
                guard let self else { return }
                if self.hasDiscordWebhookConfigured {
                    self.uploadClipToDiscord(clipURL, sourceApp: sourceApp, mode: .channelUpload)
                } else {
                    self.showDiscordWebhookSetupGuide()
                }
            },
            onDiscordDM: { [weak self] in
                guard let self else { return }
                if self.hasDiscordWebhookConfigured {
                    self.uploadClipToDiscord(clipURL, sourceApp: sourceApp, mode: .directMessageHandoff)
                } else {
                    self.showDiscordWebhookSetupGuide()
                }
            }
        )
    }

    private func uploadClipToDiscord(_ clipURL: URL, sourceApp: ClipSourceApp?, mode: DiscordShareMode = .channelUpload) {
        let webhookURL = discordWebhookURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !webhookURL.isEmpty else {
            postClipFailedNotification(
                sourceApp: sourceApp,
                title: "Discord not connected",
                message: "Add a Discord webhook URL in Settings before sending clips there."
            )
            return
        }

        guard activeDiscordUploadPaths.insert(clipURL.path).inserted else {
            statusText = "Discord upload already in progress"
            return
        }

        statusText = "Uploading clip to Discord…"
        let modeLabel = mode == .directMessageHandoff ? "dm" : "channel"
        log("discord upload requested file=\(clipURL.lastPathComponent) mode=\(modeLabel)")

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.activeDiscordUploadPaths.remove(clipURL.path) }

            do {
                let uploadedURL = try await self.discordWebhookManager.uploadClip(
                    fileURL: clipURL,
                    webhookURLString: webhookURL,
                    message: self.discordUploadMessage(for: clipURL, sourceApp: sourceApp)
                )
                if mode == .directMessageHandoff {
                    if let uploadedURL {
                        self.copyToPasteboard(uploadedURL.absoluteString, statusMessage: "Copied Discord link")
                    }
                    self.openDiscord()
                    self.statusText = uploadedURL == nil
                        ? "Opened Discord after upload"
                        : "Copied Discord link and opened Discord"
                } else {
                    self.statusText = "Uploaded \(clipURL.lastPathComponent) to Discord"
                }

                self.postDiscordUploadSuccessNotification(
                    for: clipURL,
                    uploadedURL: uploadedURL,
                    sourceApp: sourceApp,
                    mode: mode
                )
                self.log("discord upload succeeded file=\(clipURL.lastPathComponent) mode=\(modeLabel) uploadedURL=\(uploadedURL?.absoluteString ?? "none")")
            } catch {
                self.statusText = error.localizedDescription
                self.log("discord upload failed file=\(clipURL.lastPathComponent) mode=\(modeLabel) message=\(error.localizedDescription)")
                self.postClipFailedNotification(
                    sourceApp: sourceApp,
                    title: "Discord upload failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func discordUploadMessage(for clipURL: URL, sourceApp: ClipSourceApp?) -> String {
        let sourceName = sourceApp?.name ?? "MacClipper"
        return "\(sourceName) clip • \(clipURL.deletingPathExtension().lastPathComponent)"
    }

    private func postDiscordConnectionSuccessNotification() {
        if enableGameNotifications {
            GameNotificationManager.shared.show(
                title: "Discord channel connected",
                message: "MacClipper can now send clips to your configured Discord webhook channel.",
                sourceApp: nil
            )
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Discord channel connected"
        content.body = "MacClipper can now send clips to your configured Discord webhook channel."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "discord-connected-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("MacClipper Discord connection notification error: \(error.localizedDescription)")
            }
        }
    }

    private func postDiscordUploadSuccessNotification(
        for clipURL: URL,
        uploadedURL: URL?,
        sourceApp: ClipSourceApp?,
        mode: DiscordShareMode
    ) {
        let title: String
        let message: String

        switch mode {
        case .channelUpload:
            title = "Sent to Discord"
            message = uploadedURL == nil
                ? "Uploaded to your connected Discord channel."
                : "Uploaded to Discord. You can also copy the hosted link."
        case .directMessageHandoff:
            title = "Ready for Discord DM"
            message = uploadedURL == nil
                ? "Uploaded to your Discord channel and opened Discord. Forward it from the channel if needed."
                : "Uploaded to your Discord channel, copied the hosted link, and opened Discord so you can paste it into any DM."
        }

        if enableGameNotifications {
            var actions: [GameNotificationAction] = [
                GameNotificationAction(title: "Reveal", systemImage: "folder.fill", tint: MacClipperTheme.ember) { [weak self] in
                    self?.revealClip(at: clipURL)
                }
            ]

            if let uploadedURL {
                actions.append(
                    GameNotificationAction(title: "Copy Link", systemImage: "link", tint: MacClipperTheme.cyan) { [weak self] in
                        self?.copyToPasteboard(uploadedURL.absoluteString)
                    }
                )
            }

            if mode == .directMessageHandoff {
                actions.append(
                    GameNotificationAction(title: "Open Discord", systemImage: "bubble.left.and.bubble.right.fill", tint: MacClipperTheme.cyan) { [weak self] in
                        self?.openDiscord()
                    }
                )
            }

            GameNotificationManager.shared.show(
                title: title,
                message: message,
                sourceApp: sourceApp,
                previewURL: clipURL,
                actions: actions
            )
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "discord-upload-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("MacClipper Discord success notification error: \(error.localizedDescription)")
            }
        }
    }

    private func copyToPasteboard(_ value: String, statusMessage: String = "Copied Discord link") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        statusText = statusMessage
    }

    private func log(_ message: String) {
        AppLogger.shared.log("App", message)
    }

    private func openDiscord() {
        if let applicationURL = Self.discordApplicationURL() {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { _, error in
                if let error {
                    NSLog("MacClipper Discord open error: \(error.localizedDescription)")
                }
            }
            return
        }

        if let webURL = URL(string: "https://discord.com/channels/@me") {
            NSWorkspace.shared.open(webURL)
        }
    }

    private static func discordApplicationURL() -> URL? {
        let bundleIdentifiers = [
            "com.hnc.Discord",
            "com.hnc.DiscordPTB",
            "com.hnc.DiscordCanary",
            "com.hnc.DiscordDevelopment"
        ]

        for bundleIdentifier in bundleIdentifiers {
            if let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return applicationURL
            }
        }

        return nil
    }

    private func postClipFailedNotification(sourceApp: ClipSourceApp?, title: String, message: String) {
        if enableGameNotifications {
            GameNotificationManager.shared.show(title: title, message: message, sourceApp: sourceApp)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "clip-failed-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("MacClipper failure notification error: \(error.localizedDescription)")
            }
        }
    }

    private func postBufferWarmupNotificationIfNeeded(sourceApp: ClipSourceApp?) {
        let now = Date()
        if let lastWarmupNotificationAt,
           now.timeIntervalSince(lastWarmupNotificationAt) < 4 {
            return
        }
        lastWarmupNotificationAt = now

        let title = sourceApp.map { "\($0.name) capture warming up" } ?? "Capture warming up"
        let message = "Try clipping again in a second."

        if enableGameNotifications {
            GameNotificationManager.shared.show(
                title: title,
                message: message,
                sourceApp: sourceApp
            )
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "buffer-warmup-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("MacClipper warmup notification error: \(error.localizedDescription)")
            }
        }
    }

    private func applyLoadedClips(
        _ loadedClips: [SavedClip],
        preferredLastClipURL: URL?,
        preferredSelectedClipURL: URL?
    ) {
        clips = loadedClips

        if let preferredLastClipURL,
           let matched = loadedClips.first(where: { $0.url == preferredLastClipURL }) {
            selectedClip = matched
        } else if let preferredSelectedClipURL,
                  let matched = loadedClips.first(where: { $0.url == preferredSelectedClipURL }) {
            selectedClip = matched
        } else {
            selectedClip = loadedClips.first
        }
    }

    private func insertSavedClipIntoLibrary(_ clipURL: URL, sourceApp: ClipSourceApp?, capturedAt: Date) {
        guard let savedClip = ClipLibraryLoader.makeSavedClip(
            from: clipURL,
            fallbackCreatedAt: capturedAt,
            sourceAppOverride: sourceApp
        ) else {
            reloadClips()
            return
        }

        clips.removeAll { $0.url == clipURL }
        let insertionIndex = clips.firstIndex(where: { $0.createdAt < savedClip.createdAt }) ?? clips.endIndex
        clips.insert(savedClip, at: insertionIndex)
        selectedClip = savedClip
    }

    private func applyCaptureDeviceProfile(_ profile: CaptureDeviceSettingsProfile) {
        clipDuration = Self.normalizedClipDuration(profile.clipDuration)
        includeMicrophone = profile.includeMicrophone
        captureSystemAudio = profile.captureSystemAudio
        systemAudioLevel = Self.resolvedSystemAudioLevel(
            persistedLevel: profile.systemAudioLevel,
            persistedMicrophoneLevel: profile.microphoneAudioLevel
        )
        microphoneAudioLevel = Self.normalizedMicrophoneAudioLevel(profile.microphoneAudioLevel ?? 1.0)
        showCursor = profile.showCursor
        captureResolutionPreset = resolvedCaptureResolutionPreset(for: profile.captureResolutionPreset)
        videoQualityPreset = effectiveVideoQualityPreset(for: profile.videoQualityPreset, resolutionPreset: captureResolutionPreset)
    }

    private func persistCaptureDeviceProfile(for displayID: String) {
        guard !displayID.isEmpty else { return }

        captureDeviceProfiles[displayID] = CaptureDeviceSettingsProfile(
            clipDuration: Self.normalizedClipDuration(clipDuration),
            includeMicrophone: includeMicrophone,
            captureSystemAudio: captureSystemAudio,
            systemAudioLevel: systemAudioLevel,
            microphoneAudioLevel: microphoneAudioLevel,
            showCursor: showCursor,
            captureResolutionPreset: captureResolutionPreset,
            videoQualityPreset: videoQualityPreset
        )

        guard let data = try? JSONEncoder().encode(captureDeviceProfiles) else { return }
        defaults.set(data, forKey: Self.captureDeviceProfilesKey)
    }

    private static func loadClipDuration(from defaults: UserDefaults) -> Double {
        if let number = defaults.object(forKey: "clipDuration") as? NSNumber {
            return normalizedClipDuration(number.doubleValue)
        }

        if let stringValue = defaults.string(forKey: "clipDuration"),
           let parsedValue = Double(stringValue) {
            return normalizedClipDuration(parsedValue)
        }

        return 30
    }

    private static func normalizedClipDuration(_ duration: Double) -> Double {
        min(120, max(15, (duration / 5).rounded() * 5))
    }

    private static func normalizedSystemAudioLevel(_ level: Double) -> Double {
        min(1.0, max(0.0, (level * 20).rounded() / 20))
    }

    private static func normalizedMicrophoneAudioLevel(_ level: Double) -> Double {
        min(2.0, max(0.0, (level * 20).rounded() / 20))
    }

    private static func resolvedSystemAudioLevel(
        persistedLevel: Double?,
        persistedMicrophoneLevel: Double?
    ) -> Double {
        let legacyDefaultLevel = 0.75
        let recommendedLevel = 0.60

        guard let persistedLevel else {
            return recommendedLevel
        }

        if persistedMicrophoneLevel == nil, abs(persistedLevel - legacyDefaultLevel) < 0.001 {
            return recommendedLevel
        }

        return normalizedSystemAudioLevel(persistedLevel)
    }

    private static func logTimestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func persistSettingsSnapshot() {
        settingsStore.saveSettings(currentPersistedSettings())
    }

    private func refreshMicrophoneCaptureSuppression() {
        guard includeMicrophone else {
            microphoneCaptureSuppressed = false
            refreshVoiceCommandListenerState()
            return
        }

        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        microphoneCaptureSuppressed = authorizationStatus != .authorized && microphoneCaptureSuppressed

        if authorizationStatus == .authorized {
            microphoneCaptureSuppressed = false
        }

        refreshVoiceCommandListenerState()
    }

    private func refreshVoiceCommandListenerState() {
        voiceCommandManager.setPreferredMicrophoneDeviceID(resolvedSelectedMicrophoneDeviceID)
        voiceCommandManager.setUsesExternalMicrophoneFeed(shouldUseRecorderMicrophoneFeedForVoiceCommands)
        voiceCommandManager.start()
    }

    private func currentPersistedSettings() -> PersistedAppSettings {
        PersistedAppSettings(
            clipDuration: Self.normalizedClipDuration(clipDuration),
            startReplayBufferOnLaunch: true,
            includeMicrophone: includeMicrophone,
            selectedMicrophoneID: selectedMicrophoneID.isEmpty ? nil : selectedMicrophoneID,
            captureSystemAudio: captureSystemAudio,
            systemAudioLevel: systemAudioLevel,
            microphoneAudioLevel: microphoneAudioLevel,
            showCursor: showCursor,
            enableGameNotifications: enableGameNotifications,
            captureResolutionPreset: captureResolutionPreset,
            videoQualityPreset: videoQualityPreset,
            appUUID: appUUID,
            websiteUserID: websiteUserID.isEmpty ? nil : websiteUserID,
            unlockedPaidFeatures: FeatureActivationManager.normalizedFeatures(unlockedPaidFeatures),
            shortcutKey: shortcutKey.isEmpty ? "9" : shortcutKey,
            useCommand: useCommand,
            useShift: useShift,
            useOption: useOption,
            useControl: useControl,
            saveDirectoryPath: saveDirectoryPath,
            selectedCaptureDisplayID: selectedCaptureDisplayID,
            discordWebhookURLString: Self.lockedDiscordWebhookURL,
            automaticallyChecksForUpdates: updater.automaticallyChecksForUpdates,
            checksForUpdatesOnLaunch: updater.checksForUpdatesOnLaunch,
            captureDeviceProfiles: captureDeviceProfiles
        )
    }

    private static func loadCaptureDeviceProfiles(from defaults: UserDefaults) -> [String: CaptureDeviceSettingsProfile] {
        guard let data = defaults.data(forKey: captureDeviceProfilesKey),
              let profiles = try? JSONDecoder().decode([String: CaptureDeviceSettingsProfile].self, from: data) else {
            return [:]
        }

        return profiles
    }

    private static func loadPersistedSettings(
        from settingsStore: MachineSettingsStore,
        defaults: UserDefaults,
        defaultSaveDirectory: String
    ) -> PersistedAppSettings {
        if let storedSettings = settingsStore.loadSettings() {
            return PersistedAppSettings(
                clipDuration: normalizedClipDuration(storedSettings.clipDuration),
                startReplayBufferOnLaunch: true,
                includeMicrophone: storedSettings.includeMicrophone,
                selectedMicrophoneID: storedSettings.selectedMicrophoneID,
                captureSystemAudio: storedSettings.captureSystemAudio,
                systemAudioLevel: resolvedSystemAudioLevel(
                    persistedLevel: storedSettings.systemAudioLevel,
                    persistedMicrophoneLevel: storedSettings.microphoneAudioLevel
                ),
                microphoneAudioLevel: normalizedMicrophoneAudioLevel(storedSettings.microphoneAudioLevel ?? 1.0),
                showCursor: storedSettings.showCursor,
                enableGameNotifications: storedSettings.enableGameNotifications,
                captureResolutionPreset: storedSettings.captureResolutionPreset,
                videoQualityPreset: storedSettings.videoQualityPreset,
                appUUID: resolvedAppUUID(storedSettings.appUUID),
                websiteUserID: storedSettings.websiteUserID,
                unlockedPaidFeatures: FeatureActivationManager.normalizedFeatures(storedSettings.unlockedPaidFeatures),
                shortcutKey: storedSettings.shortcutKey.isEmpty ? "9" : storedSettings.shortcutKey,
                useCommand: storedSettings.useCommand,
                useShift: storedSettings.useShift,
                useOption: storedSettings.useOption,
                useControl: storedSettings.useControl,
                saveDirectoryPath: storedSettings.saveDirectoryPath.isEmpty ? defaultSaveDirectory : storedSettings.saveDirectoryPath,
                selectedCaptureDisplayID: storedSettings.selectedCaptureDisplayID.isEmpty ? defaultCaptureDisplayID() : storedSettings.selectedCaptureDisplayID,
                discordWebhookURLString: Self.lockedDiscordWebhookURL,
                automaticallyChecksForUpdates: storedSettings.automaticallyChecksForUpdates,
                checksForUpdatesOnLaunch: storedSettings.checksForUpdatesOnLaunch ?? false,
                captureDeviceProfiles: storedSettings.captureDeviceProfiles
            )
        }

        let migratedSettings = PersistedAppSettings(
            clipDuration: loadClipDuration(from: defaults),
            startReplayBufferOnLaunch: true,
            includeMicrophone: defaults.object(forKey: "includeMicrophone") as? Bool ?? false,
            selectedMicrophoneID: defaults.string(forKey: "selectedMicrophoneID"),
            captureSystemAudio: defaults.object(forKey: "captureSystemAudio") as? Bool ?? true,
            systemAudioLevel: resolvedSystemAudioLevel(
                persistedLevel: (defaults.object(forKey: "systemAudioLevel") as? NSNumber)?.doubleValue,
                persistedMicrophoneLevel: (defaults.object(forKey: "microphoneAudioLevel") as? NSNumber)?.doubleValue
            ),
            microphoneAudioLevel: normalizedMicrophoneAudioLevel((defaults.object(forKey: "microphoneAudioLevel") as? NSNumber)?.doubleValue ?? 1.0),
            showCursor: defaults.object(forKey: "showCursor") as? Bool ?? true,
            enableGameNotifications: defaults.object(forKey: "enableGameNotifications") as? Bool ?? true,
            captureResolutionPreset: CaptureResolutionPreset(rawValue: defaults.string(forKey: "captureResolutionPreset") ?? "automatic") ?? .automatic,
            videoQualityPreset: VideoQualityPreset(rawValue: defaults.string(forKey: "videoQualityPreset") ?? "balanced") ?? .balanced,
            appUUID: resolvedAppUUID(defaults.string(forKey: "appUUID")),
            websiteUserID: defaults.string(forKey: "websiteUserID"),
            unlockedPaidFeatures: defaults.stringArray(forKey: "unlockedPaidFeatures") ?? [],
            shortcutKey: defaults.string(forKey: "shortcutKey") ?? "9",
            useCommand: defaults.object(forKey: "useCommand") as? Bool ?? true,
            useShift: defaults.object(forKey: "useShift") as? Bool ?? true,
            useOption: defaults.object(forKey: "useOption") as? Bool ?? false,
            useControl: defaults.object(forKey: "useControl") as? Bool ?? false,
            saveDirectoryPath: defaults.string(forKey: "saveDirectoryPath") ?? defaultSaveDirectory,
            selectedCaptureDisplayID: defaults.string(forKey: "selectedCaptureDisplayID") ?? defaultCaptureDisplayID(),
            discordWebhookURLString: Self.lockedDiscordWebhookURL,
            automaticallyChecksForUpdates: defaults.object(forKey: "automaticallyChecksForUpdates") as? Bool ?? true,
            checksForUpdatesOnLaunch: defaults.object(forKey: "checksForUpdatesOnLaunch") as? Bool ?? false,
            captureDeviceProfiles: loadCaptureDeviceProfiles(from: defaults)
        )

        settingsStore.saveSettings(migratedSettings)
        return migratedSettings
    }

    private static func resolvedAppUUID(_ candidate: String?) -> String {
        let trimmedCandidate = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsedUUID = UUID(uuidString: trimmedCandidate) {
            return parsedUUID.uuidString.lowercased()
        }

        return UUID().uuidString.lowercased()
    }
}
