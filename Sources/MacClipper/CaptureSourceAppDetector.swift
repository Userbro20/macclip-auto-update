import AppKit
import Foundation

enum CaptureSourceAppDetector {
    static let desktopSourceApp = ClipSourceApp(name: "Desktop", bundleIdentifier: nil)

    private static let knownGameKeywords = [
        "roblox",
        "fortnite",
        "valorant",
        "leagueoflegends",
        "minecraft",
        "counter-strike",
        "counter strike",
        "counter strike 2",
        "cs2",
        "league of legends",
        "rocket league",
        "overwatch",
        "apex legends",
        "call of duty",
        "osu",
        "gta",
        "grand theft auto"
    ]

    private static let knownLauncherKeywords = [
        "steam",
        "epic games launcher",
        "battle.net",
        "battle net",
        "riot client",
        "gog galaxy",
        "ea app",
        "origin",
        "ubisoft connect",
        "heroic",
        "playnite",
        "lutris"
    ]

    private static let knownLauncherBundleIdentifiers: Set<String> = [
        "com.valvesoftware.steam",
        "com.epicgames.launcher",
        "net.battle.app",
        "com.riotgames.riotclient",
        "com.gog.galaxy",
        "com.ea.app",
        "com.ea.origin",
        "com.ubisoft.uplay",
        "com.heroicgameslauncher.hgl",
        "com.playnite.desktopapp"
    ]

    private static let knownGameInstallPathKeywords = [
        "/games/",
        "/steamapps/common/",
        "/epic games/",
        "/riot games/",
        "/battle.net/",
        "/blizzard/"
    ]

    private static let discordAssetAliases: [String: String] = [
        "counter-strike": "cs2",
        "counter strike": "cs2",
        "counter strike 2": "cs2",
        "grand theft auto": "gta",
        "league of legends": "league-of-legends",
        "leagueoflegends": "league-of-legends",
        "rocket league": "rocket-league",
        "apex legends": "apex-legends",
        "call of duty": "call-of-duty"
    ]

    static func captureCurrentSourceApp(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> ClipSourceApp {
        if Thread.isMainThread {
            return captureCurrentSourceAppOnMainThread(bundleIdentifier: bundleIdentifier)
        }

        var sourceApp = desktopSourceApp
        DispatchQueue.main.sync {
            sourceApp = captureCurrentSourceAppOnMainThread(bundleIdentifier: bundleIdentifier)
        }
        return sourceApp
    }

    static func discordAssetKey(for sourceApp: ClipSourceApp) -> String? {
        guard !sourceApp.isDesktopCapture else { return nil }

        let normalizedName = sourceApp.name.lowercased()
        let normalizedBundleID = sourceApp.bundleIdentifier?.lowercased() ?? ""

        if let alias = discordAssetAliases.first(where: { keyword, _ in
            normalizedName.contains(keyword) || normalizedBundleID.contains(keyword)
        })?.value {
            return alias
        }

        return sanitizedAssetKey(from: sourceApp.name)
    }

    private static func captureCurrentSourceAppOnMainThread(bundleIdentifier: String?) -> ClipSourceApp {
        guard let runningApp = NSWorkspace.shared.frontmostApplication,
              runningApp.bundleIdentifier != bundleIdentifier,
              let appName = runningApp.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !appName.isEmpty else {
            return desktopSourceApp
        }

        guard shouldTreatAsGame(runningApp, appName: appName) else {
            return desktopSourceApp
        }

        return ClipSourceApp(name: appName, bundleIdentifier: runningApp.bundleIdentifier)
    }

    private static func shouldTreatAsGame(_ runningApp: NSRunningApplication, appName: String) -> Bool {
        let normalizedAppName = appName.lowercased()
        let normalizedBundleID = runningApp.bundleIdentifier?.lowercased() ?? ""

        guard !matchesKnownLauncher(appName: normalizedAppName, bundleIdentifier: normalizedBundleID) else {
            return false
        }

        if matchesKnownGameKeyword(appName: normalizedAppName, bundleIdentifier: normalizedBundleID) {
            return true
        }

        guard let appURL = runningApp.bundleURL else {
            return false
        }

        if bundleMetadataLooksLikeGame(appURL: appURL) {
            return true
        }

        return knownGameInstallPathKeywords.contains { keyword in
            appURL.path.lowercased().contains(keyword)
        }
    }

    private static func matchesKnownGameKeyword(appName: String, bundleIdentifier: String) -> Bool {
        knownGameKeywords.contains { keyword in
            appName.contains(keyword) || bundleIdentifier.contains(keyword)
        }
    }

    private static func matchesKnownLauncher(appName: String, bundleIdentifier: String) -> Bool {
        if knownLauncherBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        return knownLauncherKeywords.contains { keyword in
            appName.contains(keyword) || bundleIdentifier.contains(keyword)
        }
    }

    private static func bundleMetadataLooksLikeGame(appURL: URL) -> Bool {
        guard let bundle = Bundle(url: appURL) else {
            return false
        }

        let categoryValues = [
            bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String,
            bundle.object(forInfoDictionaryKey: "ApplicationCategoryType") as? String
        ]

        return categoryValues
            .compactMap { $0?.lowercased() }
            .contains { $0.contains("game") }
    }

    private static func sanitizedAssetKey(from value: String) -> String {
        var key = value.lowercased()
        key = key.replacingOccurrences(of: "&", with: " and ")
        key = key.replacingOccurrences(of: "+", with: " plus ")
        key = key.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        key = key.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        key = key.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return key.isEmpty ? "game" : key
    }
}