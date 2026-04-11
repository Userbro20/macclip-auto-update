import Foundation
import AppKit
import Sparkle

struct AvailableAppcastUpdate: Equatable {
    let displayVersion: String
    let buildVersion: String
}

@MainActor
final class UpdaterManager: NSObject, ObservableObject {
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            guard !isSynchronizingAutomaticChecks else { return }
            guard automaticallyChecksForUpdates != updater.automaticallyChecksForUpdates else { return }

            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            persistUpdatePreferences()
        }
    }

    @Published var checksForUpdatesOnLaunch: Bool {
        didSet {
            guard checksForUpdatesOnLaunch != oldValue else { return }
            persistUpdatePreferences()
        }
    }

    @Published private(set) var feedURLString: String
    @Published private(set) var isChecking = false
    @Published private(set) var statusText: String
    @Published private(set) var availableUpdate: AvailableAppcastUpdate?

    private let defaults = UserDefaults.standard
    private let settingsStore: MachineSettingsStore?

    private var canCheckObservation: NSKeyValueObservation?
    private var automaticChecksObservation: NSKeyValueObservation?
    private var isSynchronizingAutomaticChecks = false
    private var didScheduleLaunchCheck = false

    private static let hostedAppcastURLString = "https://raw.githubusercontent.com/Userbro20/macclip-auto-update/main/appcast.xml"
    private static let legacyAutomaticChecksKey = "automaticallyChecksForUpdates"
    private static let launchCheckPreferenceKey = "checksForUpdatesOnLaunch"
    private static let sparkleSettingsMigratedKey = "sparkleUpdaterSettingsMigrated"

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    private var updater: SPUUpdater {
        updaterController.updater
    }

    init(
        automaticallyChecksForUpdates initialAutomaticallyChecksForUpdates: Bool? = nil,
        checksForUpdatesOnLaunch initialChecksForUpdatesOnLaunch: Bool? = nil,
        settingsStore: MachineSettingsStore? = nil
    ) {
        self.settingsStore = settingsStore
        self.automaticallyChecksForUpdates = initialAutomaticallyChecksForUpdates ?? true
        self.checksForUpdatesOnLaunch = initialChecksForUpdatesOnLaunch ?? false

        let configuredFeedURL = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        feedURLString = (configuredFeedURL?.isEmpty == false) ? configuredFeedURL! : Self.hostedAppcastURLString
        statusText = "Sparkle ready"
        availableUpdate = nil

        super.init()

        migrateLegacyAutomaticChecksIfNeeded(using: initialAutomaticallyChecksForUpdates)
        installObservers()
        startUpdater()
        scheduleLaunchUpdateCheckIfNeeded()
        synchronizeFromUpdater()
    }

    deinit {
        canCheckObservation?.invalidate()
        automaticChecksObservation?.invalidate()
    }

    var currentVersionDescription: String {
        "v\(currentVersionString) (build \(currentBuildNumber))"
    }

    var canCheckForUpdates: Bool {
        updater.canCheckForUpdates
    }

    var checkForUpdatesButtonTitle: String {
        isChecking ? "Checking…" : "Check for Updates"
    }

    func savePreferences() {
        persistUpdatePreferences()
    }

    func checkForUpdates() {
        guard updater.canCheckForUpdates else { return }

        availableUpdate = nil
        statusText = "Checking for updates…"
        updaterController.checkForUpdates(nil)
    }

    func openAvailableUpdate() {
        checkForUpdates()
    }

    private func startUpdater() {
        updaterController.startUpdater()
    }

    private func installObservers() {
        canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, change in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let canCheck = change.newValue ?? updater.canCheckForUpdates
                let isCurrentlyChecking = !canCheck
                if self.isChecking != isCurrentlyChecking {
                    self.isChecking = isCurrentlyChecking
                }

                if canCheck, self.statusText == "Checking for updates…", self.availableUpdate == nil {
                    self.statusText = "Sparkle ready"
                }
            }
        }

        automaticChecksObservation = updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, change in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let newValue = change.newValue ?? updater.automaticallyChecksForUpdates
                guard self.automaticallyChecksForUpdates != newValue else { return }

                self.isSynchronizingAutomaticChecks = true
                self.automaticallyChecksForUpdates = newValue
                self.isSynchronizingAutomaticChecks = false
                self.persistUpdatePreferences()
            }
        }
    }

    private func synchronizeFromUpdater() {
        if let resolvedFeedURL = updater.feedURL?.absoluteString,
           !resolvedFeedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            feedURLString = resolvedFeedURL
        }

        isSynchronizingAutomaticChecks = true
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        isSynchronizingAutomaticChecks = false
        isChecking = !updater.canCheckForUpdates
    }

    private func migrateLegacyAutomaticChecksIfNeeded(using initialAutomaticChecksForUpdates: Bool?) {
        guard !defaults.bool(forKey: Self.sparkleSettingsMigratedKey) else { return }

        let legacyPreference = defaults.object(forKey: Self.legacyAutomaticChecksKey) as? Bool
            ?? initialAutomaticChecksForUpdates

        if let legacyPreference {
            updater.automaticallyChecksForUpdates = legacyPreference
        }

        defaults.set(true, forKey: Self.sparkleSettingsMigratedKey)
        persistUpdatePreferences()
    }

    private func persistUpdatePreferences() {
        defaults.set(automaticallyChecksForUpdates, forKey: Self.legacyAutomaticChecksKey)
        defaults.set(checksForUpdatesOnLaunch, forKey: Self.launchCheckPreferenceKey)
        settingsStore?.updateSettings { settings in
            settings.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            settings.checksForUpdatesOnLaunch = checksForUpdatesOnLaunch
        }
    }

    private func scheduleLaunchUpdateCheckIfNeeded() {
        guard checksForUpdatesOnLaunch, !didScheduleLaunchCheck else { return }

        didScheduleLaunchCheck = true
        availableUpdate = nil
        statusText = "Checking for updates…"
        updater.checkForUpdatesInBackground()
    }

    private func updateAvailableState(using item: SUAppcastItem) {
        availableUpdate = AvailableAppcastUpdate(
            displayVersion: displayVersion(for: item),
            buildVersion: item.versionString
        )
    }

    private func displayVersion(for item: SUAppcastItem) -> String {
        let resolvedDisplayVersion = item.displayVersionString.trimmingCharacters(in: .whitespacesAndNewlines)
        return resolvedDisplayVersion.isEmpty ? item.versionString : resolvedDisplayVersion
    }

    private var currentVersionString: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }

    private var currentBuildNumber: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
    }
}

extension UpdaterManager: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateAvailableState(using: item)
        statusText = "Update \(displayVersion(for: item)) is available"
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availableUpdate = nil
        statusText = "MacClipper is up to date"
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        availableUpdate = nil
        statusText = "MacClipper is up to date"
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        updateAvailableState(using: item)
        statusText = "Downloading update \(displayVersion(for: item))…"
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        updateAvailableState(using: item)
        statusText = "Update \(displayVersion(for: item)) is ready"
    }

    func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) {
        updateAvailableState(using: item)
        statusText = "Preparing update \(displayVersion(for: item))…"
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        updateAvailableState(using: item)
        statusText = "Update \(displayVersion(for: item)) is ready to install"
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        updateAvailableState(using: item)
        statusText = "Installing update \(displayVersion(for: item))…"
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        statusText = "Restarting to finish the update…"
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        availableUpdate = nil
        statusText = error.localizedDescription
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error {
            statusText = error.localizedDescription
            availableUpdate = nil
        } else if availableUpdate == nil, statusText == "Checking for updates…" {
            statusText = "MacClipper is up to date"
        }
    }
}
