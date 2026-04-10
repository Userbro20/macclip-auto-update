import Foundation
import CryptoKit

enum PaidFeatureKey: String, CaseIterable, Codable {
    case fourKPro = "4k-pro"

    var displayName: String {
        switch self {
        case .fourKPro:
            return "4K Pro"
        }
    }
}

enum FeatureActivationManager {
    private static let activationPepper = "macclipper-app-feature-grant-v1"

    static func normalizedUserID(_ userID: String) -> String {
        userID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedFeature(_ feature: String) -> String {
        feature.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func normalizedFeatures(_ features: [String]) -> [String] {
        Array(
            Set(features.map(normalizedFeature).filter { !$0.isEmpty })
        )
        .sorted()
    }

    static func activationToken(userID: String, feature: String) -> String {
        let normalizedUserID = normalizedUserID(userID)
        let normalizedFeature = normalizedFeature(feature)
        guard !normalizedUserID.isEmpty, !normalizedFeature.isEmpty else { return "" }

        let digestInput = "\(normalizedUserID)|\(normalizedFeature)|\(activationPepper)"
        let digest = SHA256.hash(data: Data(digestInput.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func isValidActivationToken(userID: String, feature: String, token: String) -> Bool {
        let expected = activationToken(userID: userID, feature: feature)
        let provided = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !expected.isEmpty && expected == provided
    }

    static func featureDisplayName(_ feature: String) -> String {
        if let knownFeature = PaidFeatureKey(rawValue: normalizedFeature(feature)) {
            return knownFeature.displayName
        }

        return normalizedFeature(feature)
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}