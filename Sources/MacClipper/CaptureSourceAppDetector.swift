import AppKit
import Foundation

enum CaptureSourceAppDetector {
    static let desktopSourceApp = ClipSourceApp(name: "Desktop", bundleIdentifier: nil)

    private static let knownGameKeywords = [
        "roblox",
        "fortnite",
        "valorant",
        "minecraft",
        "counter-strike",
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

    private static let discordAssetAliases: [String: String] = [
        "counter-strike": "cs2",
        "grand theft auto": "gta",
        "league of legends": "league-of-legends",
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

        let normalizedAppName = appName.lowercased()
        let normalizedBundleID = runningApp.bundleIdentifier?.lowercased() ?? ""
        let isKnownGame = knownGameKeywords.contains { keyword in
            normalizedAppName.contains(keyword) || normalizedBundleID.contains(keyword)
        }

        guard isKnownGame else {
            return desktopSourceApp
        }

        return ClipSourceApp(name: appName, bundleIdentifier: runningApp.bundleIdentifier)
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