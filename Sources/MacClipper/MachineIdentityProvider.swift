import AppKit
import CryptoKit
import Darwin
import Foundation
import IOKit

struct MachineIdentity {
    let identifier: String
    let name: String
    let modelIdentifier: String
    let systemVersion: String
}

enum MachineIdentityProvider {
    static func current() -> MachineIdentity? {
        guard let platformUUID = platformUUID() else {
            return nil
        }

        return MachineIdentity(
            identifier: hashedMachineIdentifier(from: platformUUID),
            name: machineName(),
            modelIdentifier: modelIdentifier(),
            systemVersion: systemVersion()
        )
    }

    private static func hashedMachineIdentifier(from platformUUID: String) -> String {
        let namespace = (Bundle.main.bundleIdentifier ?? "local.macclipper.app").lowercased()
        let payload = Data("\(namespace)|\(platformUUID.lowercased())".utf8)
        return SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    private static func platformUUID() -> String? {
        guard let matching = IOServiceMatching("IOPlatformExpertDevice") else {
            return nil
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return nil
        }
        defer { IOObjectRelease(service) }

        guard let unmanaged = IORegistryEntryCreateCFProperty(
            service,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return nil
        }

        let value = unmanaged.takeRetainedValue()
        guard let platformUUID = value as? String else {
            return nil
        }

        let trimmedUUID = platformUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedUUID.isEmpty ? nil : trimmedUUID
    }

    private static func machineName() -> String {
        let localizedName = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return localizedName.isEmpty ? "Mac" : localizedName
    }

    private static func modelIdentifier() -> String {
        var size: Int = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0,
              size > 1 else {
            return ""
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
            return ""
        }

        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func systemVersion() -> String {
        ProcessInfo.processInfo.operatingSystemVersionString.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}