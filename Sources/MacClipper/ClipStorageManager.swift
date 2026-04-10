import Foundation

enum ClipStorageManager {
    static let clipFileExtensions: Set<String> = ["mov", "mp4", "m4v"]

    private static let managedDirectoryPrefix = "clips-"
    private static let maximumClipsPerDirectory = 400
    private static let maximumDirectorySizeBytes: Int64 = 24 * 1_024 * 1_024 * 1_024

    private struct DirectoryMetrics {
        let clipCount: Int
        let totalBytes: Int64
    }

    static func ensureRootDirectory(at rootDirectory: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    static func resolveNextSaveDirectory(for rootDirectory: URL, fileManager: FileManager = .default) throws -> URL {
        try ensureRootDirectory(at: rootDirectory, fileManager: fileManager)

        let managedDirectories = try managedClipDirectories(in: rootDirectory, fileManager: fileManager)
        if let activeDirectory = managedDirectories.last {
            let metrics = try directoryMetrics(for: activeDirectory, fileManager: fileManager)
            if shouldRollOver(metrics) {
                return try createManagedDirectory(in: rootDirectory, index: managedDirectories.count + 1, fileManager: fileManager)
            }
            return activeDirectory
        }

        let rootMetrics = try directoryMetrics(for: rootDirectory, fileManager: fileManager)
        if shouldRollOver(rootMetrics) {
            return try createManagedDirectory(in: rootDirectory, index: 1, fileManager: fileManager)
        }

        return rootDirectory
    }

    static func clipFileURLs(in rootDirectory: URL, fileManager: FileManager = .default) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var clipURLs: [URL] = []
        clipURLs.reserveCapacity(256)

        for case let url as URL in enumerator where isClipFile(url) {
            clipURLs.append(url)
        }

        return clipURLs
    }

    static func isClipFile(_ url: URL) -> Bool {
        clipFileExtensions.contains(url.pathExtension.lowercased())
    }

    private static func shouldRollOver(_ metrics: DirectoryMetrics) -> Bool {
        metrics.clipCount >= maximumClipsPerDirectory || metrics.totalBytes >= maximumDirectorySizeBytes
    }

    private static func managedClipDirectories(in rootDirectory: URL, fileManager: FileManager) throws -> [URL] {
        let directoryURLs = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles]
        )

        return directoryURLs
            .compactMap { url -> (Int, URL)? in
                guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .nameKey]),
                      resourceValues.isDirectory == true,
                      let name = resourceValues.name,
                      name.hasPrefix(managedDirectoryPrefix),
                      let index = Int(name.dropFirst(managedDirectoryPrefix.count)) else {
                    return nil
                }
                return (index, url)
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }

    private static func directoryMetrics(for directory: URL, fileManager: FileManager) throws -> DirectoryMetrics {
        let contentURLs = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var clipCount = 0
        var totalBytes: Int64 = 0

        for url in contentURLs where isClipFile(url) {
            guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  resourceValues.isRegularFile != false else {
                continue
            }

            clipCount += 1
            totalBytes += Int64(resourceValues.fileSize ?? 0)
        }

        return DirectoryMetrics(clipCount: clipCount, totalBytes: totalBytes)
    }

    private static func createManagedDirectory(in rootDirectory: URL, index: Int, fileManager: FileManager) throws -> URL {
        let directoryURL = rootDirectory.appendingPathComponent(
            "\(managedDirectoryPrefix)\(String(format: "%04d", index))",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}