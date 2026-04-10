import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreGraphics
import AppKit
import QuartzCore

enum CaptureResolutionPreset: String, CaseIterable, Codable, Identifiable {
    case automatic
    case p720
    case p1080
    case p1440
    case p2160

    var id: String { rawValue }

    static let highestFreePreset: CaptureResolutionPreset = .p1440

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .p720: return "720p"
        case .p1080: return "1080p"
        case .p1440: return "1440p"
        case .p2160: return "4K Pro"
        }
    }

    var requires4KProUnlock: Bool {
        self == .p2160
    }

    var targetSize: CGSize? {
        switch self {
        case .automatic:
            return nil
        case .p720:
            return CGSize(width: 1280, height: 720)
        case .p1080:
            return CGSize(width: 1920, height: 1080)
        case .p1440:
            return CGSize(width: 2560, height: 1440)
        case .p2160:
            return CGSize(width: 3840, height: 2160)
        }
    }
}

enum VideoQualityPreset: String, CaseIterable, Codable, Identifiable {
    case performance
    case balanced
    case highest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .performance: return "Performance"
        case .balanced: return "Balanced"
        case .highest: return "Highest"
        }
    }

    var preferredFramesPerSecond: Int32 {
        switch self {
        case .performance:
            return 30
        case .balanced, .highest:
            return 60
        }
    }

    var bitrateMultiplier: Double {
        switch self {
        case .performance:
            return 4.5
        case .balanced:
            return 8.0
        case .highest:
            return 12.0
        }
    }
}

struct RecorderSettings {
    var clipDuration: TimeInterval
    var saveDirectory: URL
    var includeMicrophone: Bool
    var preferredMicrophoneDeviceID: String?
    var captureSystemAudio: Bool
    var showCursor: Bool
    var preferredDisplayID: UInt32?
    var resolutionPreset: CaptureResolutionPreset
    var videoQuality: VideoQualityPreset
}

enum RecorderError: LocalizedError {
    case screenPermissionDenied
    case microphonePermissionDenied
    case noDisplayAvailable
    case noBufferedClip
    case bufferNotReady(requestedSeconds: Int, availableSeconds: Int)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .screenPermissionDenied:
            return "Screen recording permission was denied."
        case .microphonePermissionDenied:
            return "Microphone permission was denied."
        case .noDisplayAvailable:
            return "No display is available to capture."
        case .noBufferedClip:
            return "Capture is still warming up. Try again in a moment."
        case .bufferNotReady(let requestedSeconds, let availableSeconds):
            if availableSeconds <= 0 {
                return "Capture is still filling. Wait about \(requestedSeconds) seconds, then try again."
            }
            return "Only \(availableSeconds) of \(requestedSeconds) seconds are buffered so far. Wait a bit longer and try again."
        case .exportFailed(let message):
            return "Clip export failed: \(message)"
        }
    }
}

struct ReplayCapturePoint: Sendable {
    let requestedAt: Date
    let latestScreenPTS: CMTime?
}

private struct SegmentInfo: Sendable {
    let url: URL
    let startedAt: Date
    let endedAt: Date
    let startPTS: CMTime
    let endPTS: CMTime
    let duration: TimeInterval
}

private struct SegmentExportPlan: Sendable {
    let url: URL
    let localStart: TimeInterval
    let duration: TimeInterval
}

private struct PreparedSegment: Sendable {
    let url: URL
    let startedAt: Date
    let endedAt: Date
    let startPTS: CMTime
    let endPTS: CMTime
    let duration: TimeInterval
}

private struct ScreenSampleDescriptor: Equatable, Sendable {
    let width: Int
    let height: Int
    let mediaSubType: FourCharCode

    var displaySize: CGSize {
        CGSize(width: width, height: height)
    }

    var logDescription: String {
        let bigEndian = mediaSubType.bigEndian
        let bytes = [
            UInt8((bigEndian >> 24) & 0xFF),
            UInt8((bigEndian >> 16) & 0xFF),
            UInt8((bigEndian >> 8) & 0xFF),
            UInt8(bigEndian & 0xFF)
        ]
        let subtypeText = bytes.allSatisfy { $0 >= 32 && $0 <= 126 }
            ? String(decoding: bytes, as: UTF8.self)
            : String(format: "0x%08X", mediaSubType)
        return "\(width)x\(height) \(subtypeText)"
    }
}

private enum SampleAppendResult {
    case appended
    case dropped
    case resetNeeded(String)
}

final class ReplayBufferRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let recorderQueue = DispatchQueue(label: "MacClipper.replay-buffer.queue")
    private let bufferDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MacClipperBuffer", isDirectory: true)
    private let segmentDuration: TimeInterval = 1
    private let clipCaptureGrace: TimeInterval = 0.15
    private let minimumClipDuration: TimeInterval = 0.1
    private let safetyMargin: TimeInterval = 12
    private let exportTimeoutPadding: TimeInterval = 8

    var onUnexpectedStop: (@MainActor (Error) -> Void)?
    var onMicrophoneSampleBuffer: ((CMSampleBuffer) -> Void)?

    private var stream: SCStream?
    private var currentWriter: LiveSegmentWriter?
    private var segments: [SegmentInfo] = []
    private var pendingSegmentTasks: [UUID: Task<SegmentInfo?, Never>] = [:]
    private var recordingStartedAt: Date?
    private var displaySize = CGSize(width: 1280, height: 720)
    private var suppressUnexpectedStopCallback = false
    private var currentSettings = RecorderSettings(
        clipDuration: 30,
        saveDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/MacClipper", isDirectory: true),
        includeMicrophone: true,
        preferredMicrophoneDeviceID: nil,
        captureSystemAudio: true,
        showCursor: true,
        preferredDisplayID: nil,
        resolutionPreset: .automatic,
        videoQuality: .balanced
    )

    func update(settings: RecorderSettings) {
        recorderQueue.sync {
            self.currentSettings = settings
        }
    }

    func makeCapturePoint() -> ReplayCapturePoint {
        recorderQueue.sync {
            let latestPTS = currentWriter?.latestPTS ?? segments.last?.endPTS
            return ReplayCapturePoint(requestedAt: Date(), latestScreenPTS: latestPTS)
        }
    }

    func start(with settings: RecorderSettings, preservingBuffer: Bool = false) async throws {
        log(
            "start requested preservingBuffer=\(preservingBuffer) clipDuration=\(Int(settings.clipDuration)) display=\(settings.preferredDisplayID.map(String.init) ?? "auto") microphone=\(settings.includeMicrophone ? (settings.preferredMicrophoneDeviceID ?? "system-default") : "off")"
        )
        if recorderQueue.sync(execute: { self.stream != nil }) {
            await stop()
        }

        update(settings: settings)
        if preservingBuffer {
            await flushPendingSegments()
        }
        let shareableContent = try await loadShareableContentEnsuringPermissions(includeMicrophone: settings.includeMicrophone)
        try prepareDirectories(saveDirectory: settings.saveDirectory, resetBuffer: !preservingBuffer)

        guard let display = Self.preferredDisplay(from: shareableContent.displays, preferredDisplayID: settings.preferredDisplayID) else {
            throw RecorderError.noDisplayAvailable
        }

        let nativeCaptureSize = Self.nativeCaptureSize(for: display)
        let targetCaptureSize = Self.captureSize(for: nativeCaptureSize, preset: settings.resolutionPreset)
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(targetCaptureSize.width.rounded())
        configuration.height = Int(targetCaptureSize.height.rounded())
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: settings.videoQuality.preferredFramesPerSecond)
        configuration.queueDepth = settings.videoQuality == .performance ? 8 : 12
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = settings.showCursor
        configuration.capturesAudio = settings.captureSystemAudio
        configuration.captureMicrophone = settings.includeMicrophone
        configuration.microphoneCaptureDeviceID = settings.includeMicrophone ? settings.preferredMicrophoneDeviceID : nil
        configuration.excludesCurrentProcessAudio = false
        configuration.sampleRate = 48_000
        configuration.channelCount = 2

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: recorderQueue)

        if settings.captureSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: recorderQueue)
        }

        if settings.includeMicrophone {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: recorderQueue)
        }

        recorderQueue.sync {
            self.displaySize = targetCaptureSize
            self.currentWriter = nil
            if !preservingBuffer {
                self.segments.removeAll()
            }
            self.pendingSegmentTasks.removeAll()
            self.recordingStartedAt = Date()
            self.suppressUnexpectedStopCallback = false
            self.trimOldSegments(now: Date())
        }

        try await stream.startCapture()
        log("capture started")

        recorderQueue.sync {
            self.stream = stream
        }
    }

    func stop() async {
        log("stop requested")
        let stream = recorderQueue.sync { () -> SCStream? in
            self.suppressUnexpectedStopCallback = true
            let existingStream = self.stream
            self.stream = nil
            return existingStream
        }

        try? await stream?.stopCapture()
        await flushPendingSegments()

        if let finalizedSegment = await finalizeCurrentWriter() {
            recorderQueue.sync {
                self.storeFinalizedSegment(finalizedSegment)
            }
        }

        await flushPendingSegments()

        recorderQueue.sync {
            self.currentWriter = nil
            self.segments.removeAll()
            self.pendingSegmentTasks.removeAll()
            self.recordingStartedAt = nil
        }

        try? FileManager.default.removeItem(at: bufferDirectory)
        log("capture stopped and buffer cleared")
    }

    func saveReplayClip(
        capturePoint: ReplayCapturePoint = ReplayCapturePoint(requestedAt: Date(), latestScreenPTS: nil),
        suppressMicrophoneInExport: Bool = false
    ) async throws -> URL {
        log("saveReplayClip requested latestPTS=\(capturePoint.latestScreenPTS?.seconds ?? -1)")
        let settings = recorderQueue.sync { currentSettings }

        if clipCaptureGrace > 0 {
            try? await Task.sleep(nanoseconds: UInt64(clipCaptureGrace * 1_000_000_000))
        }

        await flushPendingSegments()

        if let finalizedSegment = await finalizeCurrentWriter() {
            recorderQueue.sync {
                self.storeFinalizedSegment(finalizedSegment)
            }
        }

        await flushPendingSegments()

        let snapshot = recorderQueue.sync {
            segments.sorted { $0.endedAt < $1.endedAt }
        }
        log("segment snapshot count=\(snapshot.count)")

        guard !snapshot.isEmpty else {
            log("saveReplayClip failed: no buffered segments")
            throw RecorderError.noBufferedClip
        }

        let preparedSegments = await prepareSegments(from: snapshot)
        guard !preparedSegments.isEmpty else {
            log("saveReplayClip failed: prepared segments empty")
            throw RecorderError.noBufferedClip
        }

        let requestedEndDate = capturePoint.requestedAt
        let latestPreparedEndDate = preparedSegments.last?.endedAt ?? requestedEndDate
        let exportEndDate = min(requestedEndDate, latestPreparedEndDate)
        let tailGap = max(0, requestedEndDate.timeIntervalSince(latestPreparedEndDate))

        let availableDuration = preparedSegments.reduce(into: 0.0) { runningTotal, segment in
            let segmentEndDate = min(segment.endedAt, exportEndDate)
            runningTotal += max(0, segmentEndDate.timeIntervalSince(segment.startedAt))
        }
        log("prepared segments count=\(preparedSegments.count) availableDuration=\(String(format: "%.2f", availableDuration))")
        if tailGap > 0.01 {
            log("clip request tail gap=\(String(format: "%.2f", tailGap)) seconds before the shortcut")
        }

        guard availableDuration >= minimumClipDuration else {
            log("saveReplayClip failed: availableDuration below minimum")
            throw RecorderError.noBufferedClip
        }

        let effectiveClipDuration = min(settings.clipDuration, availableDuration)
        var exportPlan: [SegmentExportPlan] = []
        var remainingDuration = effectiveClipDuration
        var cursorEndDate = exportEndDate

        for segment in preparedSegments.reversed() {
            let segmentEndDate = min(segment.endedAt, cursorEndDate)
            let usableDuration = max(0, segmentEndDate.timeIntervalSince(segment.startedAt))
            guard usableDuration > 0.01 else { continue }

            let durationToTake = min(remainingDuration, usableDuration)
            let localEndOffset = max(0, segmentEndDate.timeIntervalSince(segment.startedAt))
            let localStart = max(0, localEndOffset - durationToTake)
            exportPlan.append(
                SegmentExportPlan(
                    url: segment.url,
                    localStart: localStart,
                    duration: durationToTake
                )
            )

            remainingDuration -= durationToTake
            cursorEndDate = min(cursorEndDate, segment.startedAt)
            if remainingDuration <= 0.01 {
                break
            }
        }

        guard !exportPlan.isEmpty else {
            log("saveReplayClip failed: export plan empty")
            throw RecorderError.noBufferedClip
        }

        let outputURL = try await exportClip(
            from: exportPlan.reversed(),
            targetDuration: effectiveClipDuration,
            videoQuality: settings.videoQuality,
            saveDirectory: settings.saveDirectory,
            captureSystemAudio: settings.captureSystemAudio,
            includeMicrophoneInExport: settings.includeMicrophone && !suppressMicrophoneInExport
        )
        log("saveReplayClip completed output=\(outputURL.lastPathComponent)")
        return outputURL
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        handleSampleBuffer(sampleBuffer, outputType: outputType)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log("stream stopped unexpectedly: \(error.localizedDescription)")
        let stoppedStreamID = ObjectIdentifier(stream)

        recorderQueue.async {
            let shouldNotify = !self.suppressUnexpectedStopCallback
            let writerToFinalize = self.currentWriter

            if let currentStream = self.stream,
               ObjectIdentifier(currentStream) == stoppedStreamID {
                self.stream = nil
            }

            self.currentWriter = nil
            self.recordingStartedAt = nil
            if let writerToFinalize {
                self.enqueuePendingSegmentFinalization(for: writerToFinalize)
            }
            self.trimOldSegments(now: Date())

            guard shouldNotify else { return }

            Task { @MainActor [weak self] in
                self?.onUnexpectedStop?(error)
            }
        }
    }

    private func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer, outputType: SCStreamOutputType) {
        let settings = currentSettings
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let screenDescriptor = outputType == .screen ? Self.screenSampleDescriptor(from: sampleBuffer) : nil
        let sampleDisplaySize = outputType == .screen
            ? (Self.screenDisplaySize(from: sampleBuffer) ?? displaySize)
            : displaySize

        if outputType == .audio && !settings.captureSystemAudio { return }
        if outputType == .microphone && !settings.includeMicrophone { return }

        if outputType == .screen,
           !Self.isRecordableScreenSample(sampleBuffer) {
            return
        }

        if outputType == .microphone {
            onMicrophoneSampleBuffer?(sampleBuffer)
        }

        if outputType == .screen,
           displaySize != sampleDisplaySize {
            displaySize = sampleDisplaySize
            log("screen sample size updated size=\(Int(sampleDisplaySize.width))x\(Int(sampleDisplaySize.height))")
        }

        if outputType == .screen,
           let currentWriter,
           let screenDescriptor,
           !currentWriter.matchesScreenSample(screenDescriptor, displaySize: sampleDisplaySize) {
            log("screen format changed from \(currentWriter.screenDescriptorLogDescription) to \(screenDescriptor.logDescription); rotating writer")
            enqueuePendingSegmentFinalization(for: currentWriter)
            self.currentWriter = nil
        }

        if currentWriter == nil {
            guard outputType == .screen else { return }
            currentWriter = Self.makeWriter(
                in: bufferDirectory,
                displaySize: sampleDisplaySize,
                includeMicrophone: settings.includeMicrophone,
                captureSystemAudio: settings.captureSystemAudio,
                videoQuality: settings.videoQuality,
                screenFormatHint: Self.screenFormatDescription(from: sampleBuffer),
                screenSampleDescriptor: screenDescriptor
            )
        } else if outputType == .screen,
                  currentWriter?.shouldRotate(at: timestamp, segmentDuration: segmentDuration) == true {
            if let writerToFinish = currentWriter {
                enqueuePendingSegmentFinalization(for: writerToFinish)
            }

            currentWriter = Self.makeWriter(
                in: bufferDirectory,
                displaySize: sampleDisplaySize,
                includeMicrophone: settings.includeMicrophone,
                captureSystemAudio: settings.captureSystemAudio,
                videoQuality: settings.videoQuality,
                screenFormatHint: Self.screenFormatDescription(from: sampleBuffer),
                screenSampleDescriptor: screenDescriptor
            )
        }

        let appendResult = currentWriter?.append(sampleBuffer, as: outputType) ?? .dropped

        switch appendResult {
        case .appended:
            break
        case .dropped:
            return
        case .resetNeeded(let reason):
            log("writer reset needed outputType=\(outputType.rawValue) reason=\(reason)")
            currentWriter?.cancelAndDiscard()
            currentWriter = nil

            guard outputType == .screen else { return }

            currentWriter = Self.makeWriter(
                in: bufferDirectory,
                displaySize: sampleDisplaySize,
                includeMicrophone: settings.includeMicrophone,
                captureSystemAudio: settings.captureSystemAudio,
                videoQuality: settings.videoQuality,
                screenFormatHint: Self.screenFormatDescription(from: sampleBuffer),
                screenSampleDescriptor: screenDescriptor
            )

            let retryResult = currentWriter?.append(sampleBuffer, as: outputType) ?? .dropped
            switch retryResult {
            case .appended:
                log("writer recovered after retry")
            case .dropped:
                log("writer retry dropped first screen sample")
                return
            case .resetNeeded(let retryReason):
                log("writer retry failed reason=\(retryReason)")
                currentWriter?.cancelAndDiscard()
                currentWriter = nil
                return
            }
        }

        trimOldSegments(now: Date())
    }

    private func enqueuePendingSegmentFinalization(for writer: LiveSegmentWriter) {
        let taskID = UUID()
        let task = Task.detached(priority: .utility) { await writer.finish() }
        pendingSegmentTasks[taskID] = task

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let finalizedSegment = await task.value

            self.recorderQueue.async {
                guard self.pendingSegmentTasks.removeValue(forKey: taskID) != nil else { return }
                guard let finalizedSegment else { return }
                self.storeFinalizedSegment(finalizedSegment)
            }
        }
    }

    private func flushPendingSegments() async {
        let pendingTasks = recorderQueue.sync { pendingSegmentTasks }

        for (taskID, task) in pendingTasks {
            let finalizedSegment = await task.value

            recorderQueue.sync {
                guard self.pendingSegmentTasks.removeValue(forKey: taskID) != nil else { return }
                guard let finalizedSegment else { return }
                self.storeFinalizedSegment(finalizedSegment)
            }
        }
    }

    private func finalizeCurrentWriter() async -> SegmentInfo? {
        let writer = recorderQueue.sync { () -> LiveSegmentWriter? in
            let existingWriter = self.currentWriter
            self.currentWriter = nil
            return existingWriter
        }

        return await writer?.finish()
    }

    private func storeFinalizedSegment(_ segment: SegmentInfo) {
        segments.append(segment)
        segments.sort { $0.endedAt < $1.endedAt }
        trimOldSegments(now: Date())
    }

    private func trimOldSegments(now currentTime: Date) {
        let keepDuration = currentSettings.clipDuration + safetyMargin
        let cutoffDate = currentTime.addingTimeInterval(-keepDuration)

        let expiredSegments = segments.filter { $0.endedAt < cutoffDate }
        segments.removeAll { $0.endedAt < cutoffDate }

        for segment in expiredSegments {
            try? FileManager.default.removeItem(at: segment.url)
        }
    }

    private func prepareDirectories(saveDirectory: URL, resetBuffer: Bool) throws {
        let fileManager = FileManager.default
        if resetBuffer {
            try? fileManager.removeItem(at: bufferDirectory)
        }
        try fileManager.createDirectory(at: bufferDirectory, withIntermediateDirectories: true)
        try ClipStorageManager.ensureRootDirectory(at: saveDirectory, fileManager: fileManager)
    }

    private func loadShareableContentEnsuringPermissions(includeMicrophone: Bool) async throws -> SCShareableContent {
        let screenAllowed = await MainActor.run {
            CGPreflightScreenCaptureAccess()
        }

        let shareableContent: SCShareableContent
        do {
            shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            if screenAllowed {
                throw error
            }
            throw RecorderError.screenPermissionDenied
        }

        if !screenAllowed && shareableContent.displays.isEmpty {
            throw RecorderError.screenPermissionDenied
        }

        if includeMicrophone {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                break
            case .notDetermined, .denied, .restricted:
                throw RecorderError.microphonePermissionDenied
            @unknown default:
                throw RecorderError.microphonePermissionDenied
            }
        }

        return shareableContent
    }

    private static func nativeCaptureSize(for display: SCDisplay) -> CGSize {
        if let mode = CGDisplayCopyDisplayMode(display.displayID) {
            return CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
        }

        return CGSize(width: display.width, height: display.height)
    }

    private static func preferredDisplay(from displays: [SCDisplay], preferredDisplayID: UInt32?) -> SCDisplay? {
        guard !displays.isEmpty else { return nil }

        if let preferredDisplayID,
           let preferredDisplay = displays.first(where: { $0.displayID == preferredDisplayID }) {
            return preferredDisplay
        }

        let mouseLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens where screen.frame.contains(mouseLocation) {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               let matchedDisplay = displays.first(where: { $0.displayID == CGDirectDisplayID(number.uint32Value) }) {
                return matchedDisplay
            }
        }

        let mainDisplayID = CGMainDisplayID()
        if let mainDisplay = displays.first(where: { $0.displayID == mainDisplayID }) {
            return mainDisplay
        }

        return displays.first
    }

    private static func captureSize(for nativeSize: CGSize, preset: CaptureResolutionPreset) -> CGSize {
        guard let targetSize = preset.targetSize else { return nativeSize }

        let aspectRatio = nativeSize.width / max(nativeSize.height, 1)
        let maxWidth = min(nativeSize.width, targetSize.width)
        let maxHeight = min(nativeSize.height, targetSize.height)

        let widthLimitedHeight = maxWidth / aspectRatio
        if widthLimitedHeight <= maxHeight {
            return CGSize(width: roundedEven(maxWidth), height: roundedEven(widthLimitedHeight))
        }

        let heightLimitedWidth = maxHeight * aspectRatio
        return CGSize(width: roundedEven(heightLimitedWidth), height: roundedEven(maxHeight))
    }

    private static func roundedEven(_ value: CGFloat) -> CGFloat {
        let roundedValue = max(2, Int(value.rounded()))
        return CGFloat(roundedValue.isMultiple(of: 2) ? roundedValue : roundedValue - 1)
    }

    private static func makeUniqueOutputURL(in saveDirectory: URL, exportedAt: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"

        let baseName = "Clipped with MacClipper \(formatter.string(from: exportedAt))"
        var candidateURL = saveDirectory.appendingPathComponent(baseName).appendingPathExtension("mov")
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidateURL.path) {
            candidateURL = saveDirectory
                .appendingPathComponent("\(baseName) \(suffix)")
                .appendingPathExtension("mov")
            suffix += 1
        }

        return candidateURL
    }

    private static func makeWriter(
        in directory: URL,
        displaySize: CGSize,
        includeMicrophone: Bool,
        captureSystemAudio: Bool,
        videoQuality: VideoQualityPreset,
        screenFormatHint: CMFormatDescription?,
        screenSampleDescriptor: ScreenSampleDescriptor?
    ) -> LiveSegmentWriter {
        let fileURL = directory.appendingPathComponent("segment-\(UUID().uuidString).mov")
        return LiveSegmentWriter(
            url: fileURL,
            displaySize: displaySize,
            includeMicrophone: includeMicrophone,
            captureSystemAudio: captureSystemAudio,
            videoQuality: videoQuality,
            screenFormatHint: screenFormatHint,
            screenSampleDescriptor: screenSampleDescriptor
        )
    }

    private static func screenFormatDescription(from sampleBuffer: CMSampleBuffer) -> CMFormatDescription? {
        CMSampleBufferGetFormatDescription(sampleBuffer)
    }

    private static func screenSampleDescriptor(from sampleBuffer: CMSampleBuffer) -> ScreenSampleDescriptor? {
        guard let formatDescription = screenFormatDescription(from: sampleBuffer) else {
            return nil
        }

        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        guard dimensions.width > 0, dimensions.height > 0 else {
            return nil
        }

        return ScreenSampleDescriptor(
            width: Int(dimensions.width),
            height: Int(dimensions.height),
            mediaSubType: CMFormatDescriptionGetMediaSubType(formatDescription)
        )
    }

    private static func screenDisplaySize(from sampleBuffer: CMSampleBuffer) -> CGSize? {
        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let width = CVPixelBufferGetWidth(imageBuffer)
            let height = CVPixelBufferGetHeight(imageBuffer)
            guard width > 0, height > 0 else { return nil }
            return CGSize(width: width, height: height)
        }

        return screenSampleDescriptor(from: sampleBuffer)?.displaySize
    }

    private static func screenFrameStatus(from sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let rawValue = attachments[.status] as? Int else {
            return nil
        }

        return SCFrameStatus(rawValue: rawValue)
    }

    private static func isRecordableScreenSample(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return false }

        if let status = screenFrameStatus(from: sampleBuffer) {
            return status == .complete
        }

        return true
    }

    private func prepareSegments(from snapshot: [SegmentInfo]) async -> [PreparedSegment] {
        var preparedSegments: [PreparedSegment] = []
        preparedSegments.reserveCapacity(snapshot.count)

        for segment in snapshot {
            let asset = AVURLAsset(url: segment.url)
            let assetDuration = asset.duration.seconds
            let fallbackDuration = max(segment.duration, segment.endedAt.timeIntervalSince(segment.startedAt))
            let resolvedDuration: TimeInterval
            if fallbackDuration > 0.01 {
                resolvedDuration = fallbackDuration
            } else if assetDuration.isFinite {
                resolvedDuration = max(0, assetDuration)
            } else {
                resolvedDuration = 0
            }
            let resolvedEnd = segment.endPTS
            let resolvedStart = CMTimeMaximum(.zero, CMTimeSubtract(resolvedEnd, CMTime(seconds: resolvedDuration, preferredTimescale: 600)))
            let resolvedEndDate = segment.endedAt
            let resolvedStartDate = resolvedEndDate.addingTimeInterval(-resolvedDuration)

            preparedSegments.append(
                PreparedSegment(
                    url: segment.url,
                    startedAt: resolvedStartDate,
                    endedAt: resolvedEndDate,
                    startPTS: resolvedStart,
                    endPTS: resolvedEnd,
                    duration: resolvedDuration
                )
            )
        }

        return preparedSegments.sorted { $0.endedAt < $1.endedAt }
    }

    private func exportClip(
        from segments: [SegmentExportPlan],
        targetDuration: TimeInterval,
        videoQuality: VideoQualityPreset,
        saveDirectory: URL,
        captureSystemAudio: Bool,
        includeMicrophoneInExport: Bool
    ) async throws -> URL {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw RecorderError.exportFailed("Unable to create the output video track.")
        }

        var audioTracks: [AVMutableCompositionTrack] = []
        var insertTime: CMTime = .zero

        for segment in segments {
            guard segment.duration > 0 else { continue }

            let localStart = CMTime(seconds: segment.localStart, preferredTimescale: 600)
            let duration = CMTime(seconds: segment.duration, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: localStart, duration: duration)
            let asset = AVURLAsset(url: segment.url)

            if let sourceVideo = asset.tracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(timeRange, of: sourceVideo, at: insertTime)
                if videoTrack.preferredTransform == .identity {
                    videoTrack.preferredTransform = sourceVideo.preferredTransform
                }
            }

            let sourceAudioTracks = asset.tracks(withMediaType: .audio)
            let hasMultipleAudioTracks = sourceAudioTracks.count > 1
            var insertedAudioTrackCount = 0

            for sourceAudioTrack in sourceAudioTracks {
                let shouldIncludeTrack = Self.shouldIncludeAudioTrack(
                    sourceAudioTrack,
                    captureSystemAudio: captureSystemAudio,
                    includeMicrophoneInExport: includeMicrophoneInExport,
                    hasMultipleAudioTracks: hasMultipleAudioTracks
                )
                guard shouldIncludeTrack else { continue }

                if audioTracks.count <= insertedAudioTrackCount,
                   let newAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    audioTracks.append(newAudioTrack)
                }

                if insertedAudioTrackCount < audioTracks.count {
                    try audioTracks[insertedAudioTrackCount].insertTimeRange(timeRange, of: sourceAudioTrack, at: insertTime)
                    insertedAudioTrackCount += 1
                }
            }

            insertTime = CMTimeAdd(insertTime, duration)
        }

        guard insertTime > .zero else {
            throw RecorderError.noBufferedClip
        }

        let exportedAt = Date()
        let outputDirectory = try ClipStorageManager.resolveNextSaveDirectory(for: saveDirectory)
        let outputURL = Self.makeUniqueOutputURL(in: outputDirectory, exportedAt: exportedAt)
        let applyWatermark = shouldApplyWatermark(for: videoQuality)
        let exactDuration = CMTime(seconds: targetDuration, preferredTimescale: 600)
        let exportTimeRange = CMTimeRange(start: .zero, duration: CMTimeMinimum(insertTime, exactDuration))
        let exportPresets = Self.exportPresetCandidates(for: videoQuality, applyWatermark: applyWatermark)
        var lastError: Error?

        log("export starting segments=\(segments.count) targetDuration=\(String(format: "%.2f", targetDuration)) output=\(outputURL.lastPathComponent) directory=\(outputDirectory.lastPathComponent) presets=\(exportPresets.joined(separator: ","))")

        for preset in exportPresets {
            try? FileManager.default.removeItem(at: outputURL)

            guard let exporter = AVAssetExportSession(asset: composition, presetName: preset) else {
                log("export preset unavailable preset=\(preset)")
                continue
            }

            guard exporter.supportedFileTypes.contains(.mov) else {
                log("export preset missing .mov support preset=\(preset)")
                continue
            }

            exporter.timeRange = exportTimeRange
            exporter.fileLengthLimit = 0
            exporter.shouldOptimizeForNetworkUse = true
            exporter.outputURL = outputURL
            exporter.outputFileType = .mov

            if applyWatermark {
                exporter.videoComposition = makeWatermarkVideoComposition(for: composition, exportedAt: exportedAt, videoQuality: videoQuality)
            }

            do {
                log("export attempt preset=\(preset) output=\(outputURL.lastPathComponent)")
                try await performExport(with: exporter, outputURL: outputURL)
                log("export completed preset=\(preset) output=\(outputURL.lastPathComponent)")
                return outputURL
            } catch {
                lastError = error
                log("export attempt failed preset=\(preset) output=\(outputURL.lastPathComponent) message=\(error.localizedDescription)")
            }
        }

        throw lastError ?? RecorderError.exportFailed("Unable to create export session.")
    }

    private func performExport(
        with exporter: AVAssetExportSession,
        outputURL: URL
    ) async throws {
        do {
            try await exporter.export(to: outputURL, as: .mov)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            let message = (error as NSError).localizedDescription
            throw RecorderError.exportFailed(message)
        }
    }

    private func log(_ message: String) {
        AppLogger.shared.log("ReplayBuffer", message)
    }

    private func shouldApplyWatermark(for videoQuality: VideoQualityPreset) -> Bool {
        false
    }

    private static func exportPresetCandidates(for videoQuality: VideoQualityPreset, applyWatermark: Bool) -> [String] {
        if applyWatermark {
            return [AVAssetExportPresetHighestQuality, AVAssetExportPresetMediumQuality]
        }

        switch videoQuality {
        case .performance:
            return [AVAssetExportPresetPassthrough, AVAssetExportPresetMediumQuality, AVAssetExportPresetHighestQuality]
        case .balanced:
            return [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality, AVAssetExportPresetMediumQuality]
        case .highest:
            return [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
        }
    }

    private static func shouldIncludeAudioTrack(
        _ track: AVAssetTrack,
        captureSystemAudio: Bool,
        includeMicrophoneInExport: Bool,
        hasMultipleAudioTracks: Bool
    ) -> Bool {
        guard captureSystemAudio || includeMicrophoneInExport else { return false }
        guard hasMultipleAudioTracks else { return true }

        switch inferredAudioTrackRole(for: track) {
        case .system:
            return captureSystemAudio
        case .microphone:
            return includeMicrophoneInExport
        case .unknown:
            return captureSystemAudio || includeMicrophoneInExport
        }
    }

    private static func inferredAudioTrackRole(for track: AVAssetTrack) -> CapturedAudioTrackRole {
        guard let rawFormatDescription = track.formatDescriptions.first else { return .unknown }

        let formatDescription = unsafeBitCast(rawFormatDescription, to: CMFormatDescription.self)
        guard let streamDescriptionPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return .unknown
        }

        let channelCount = Int(streamDescriptionPointer.pointee.mChannelsPerFrame)
        if channelCount <= 1 {
            return .microphone
        }

        if channelCount >= 2 {
            return .system
        }

        return .unknown
    }

    private func makeWatermarkVideoComposition(
        for composition: AVMutableComposition,
        exportedAt: Date,
        videoQuality: VideoQualityPreset
    ) -> AVMutableVideoComposition {
        let videoComposition = AVMutableVideoComposition(propertiesOf: composition)
        let renderSize = videoComposition.renderSize.width > 0 && videoComposition.renderSize.height > 0
            ? videoComposition.renderSize
            : displaySize

        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: videoQuality.preferredFramesPerSecond)

        let parentLayer = CALayer()
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)

        let titleFontSize = min(max(renderSize.width * 0.035, 22), 44)
        let detailFontSize = min(max(renderSize.width * 0.018, 11), 20)
        let bottomFontSize = min(max(renderSize.width * 0.016, 10), 16)
        let scale = NSScreen.main?.backingScaleFactor ?? 2

        let centerTitleLayer = Self.makeTextLayer(
            text: "MacClipper",
            fontSize: titleFontSize,
            color: NSColor.white.withAlphaComponent(0.24),
            weight: .bold,
            scale: scale
        )
        centerTitleLayer.frame = CGRect(
            x: renderSize.width * 0.18,
            y: renderSize.height * 0.52,
            width: renderSize.width * 0.64,
            height: titleFontSize * 1.5
        )
        parentLayer.addSublayer(centerTitleLayer)

        let timestampText = Self.displayTimestamp(from: exportedAt)
        let centerDateLayer = Self.makeTextLayer(
            text: timestampText,
            fontSize: detailFontSize,
            color: NSColor.white.withAlphaComponent(0.18),
            weight: .medium,
            scale: scale
        )
        centerDateLayer.frame = CGRect(
            x: renderSize.width * 0.15,
            y: renderSize.height * 0.47,
            width: renderSize.width * 0.70,
            height: detailFontSize * 1.4
        )
        parentLayer.addSublayer(centerDateLayer)

        let bottomLayer = Self.makeTextLayer(
            text: "MacClipper • \(timestampText)",
            fontSize: bottomFontSize,
            color: NSColor(calibratedWhite: 0.96, alpha: 0.60),
            weight: .medium,
            scale: scale
        )
        bottomLayer.frame = CGRect(
            x: renderSize.width * 0.10,
            y: renderSize.height * 0.035,
            width: renderSize.width * 0.80,
            height: bottomFontSize * 1.5
        )
        parentLayer.addSublayer(bottomLayer)

        if let iconImage = Self.applicationIconCGImage() {
            let iconSize = min(max(renderSize.width * 0.055, 26), 54)
            let iconLayer = CALayer()
            iconLayer.contents = iconImage
            iconLayer.contentsGravity = .resizeAspect
            iconLayer.opacity = 0.92
            iconLayer.frame = CGRect(
                x: renderSize.width - iconSize - 18,
                y: renderSize.height - iconSize - 18,
                width: iconSize,
                height: iconSize
            )
            parentLayer.addSublayer(iconLayer)
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        return videoComposition
    }

    private static func makeTextLayer(
        text: String,
        fontSize: CGFloat,
        color: NSColor,
        weight: NSFont.Weight,
        scale: CGFloat
    ) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.string = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
                .foregroundColor: color.cgColor
            ]
        )
        textLayer.alignmentMode = .center
        textLayer.contentsScale = scale
        textLayer.isWrapped = false
        return textLayer
    }

    private static func displayTimestamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func applicationIconCGImage() -> CGImage? {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: iconURL) else {
            return nil
        }

        var proposedRect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
}

private enum CapturedAudioTrackRole {
    case system
    case microphone
    case unknown
}

private final class LiveSegmentWriter: @unchecked Sendable {
    private let finishTimeout: TimeInterval = 2.5
    private let url: URL
    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneInput: AVAssetWriterInput?
    private let finishStateQueue = DispatchQueue(label: "MacClipper.replay-buffer.writer-finish")
    private let configuredDisplaySize: CGSize
    private let screenSampleDescriptor: ScreenSampleDescriptor?

    private(set) var startPTS: CMTime?
    private(set) var latestPTS: CMTime?
    private(set) var startedAt: Date?
    private(set) var latestSampleAt: Date?
    private var hasResumedFinishContinuation = false

    init(
        url: URL,
        displaySize: CGSize,
        includeMicrophone: Bool,
        captureSystemAudio: Bool,
        videoQuality: VideoQualityPreset,
        screenFormatHint: CMFormatDescription?,
        screenSampleDescriptor: ScreenSampleDescriptor?
    ) {
        self.url = url
        self.configuredDisplaySize = displaySize
        self.screenSampleDescriptor = screenSampleDescriptor
        self.assetWriter = try! AVAssetWriter(outputURL: url, fileType: .mov)

        let pixels = max(displaySize.width * displaySize.height, 1_280 * 720)
        let targetBitRate = max(12_000_000, Int(pixels * videoQuality.bitrateMultiplier))

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(displaySize.width),
            AVVideoHeightKey: Int(displaySize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: targetBitRate,
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: false
            ]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings, sourceFormatHint: screenFormatHint)
        videoInput.expectsMediaDataInRealTime = true
        assetWriter.add(videoInput)

        if captureSystemAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            assetWriter.add(input)
            systemAudioInput = input
        } else {
            systemAudioInput = nil
        }

        if includeMicrophone {
            let microphoneSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: microphoneSettings)
            input.expectsMediaDataInRealTime = true
            assetWriter.add(input)
            microphoneInput = input
        } else {
            microphoneInput = nil
        }
    }

    var screenDescriptorLogDescription: String {
        screenSampleDescriptor?.logDescription
            ?? "\(Int(configuredDisplaySize.width))x\(Int(configuredDisplaySize.height)) unknown"
    }

    func matchesScreenSample(_ descriptor: ScreenSampleDescriptor, displaySize: CGSize) -> Bool {
        configuredDisplaySize == displaySize && screenSampleDescriptor == descriptor
    }

    func shouldRotate(at timestamp: CMTime, segmentDuration: TimeInterval) -> Bool {
        guard let startPTS else { return false }
        return timestamp.seconds - startPTS.seconds >= segmentDuration
    }

    func append(_ sampleBuffer: CMSampleBuffer, as outputType: SCStreamOutputType) -> SampleAppendResult {
        if assetWriter.status == .failed || assetWriter.status == .cancelled {
            let message = assetWriter.error?.localizedDescription ?? "writer already failed"
            return .resetNeeded(message)
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let sampleDate = Date()

        switch outputType {
        case .screen:
            if assetWriter.status == .unknown {
                guard assetWriter.startWriting() else {
                    let message = assetWriter.error?.localizedDescription ?? "startWriting failed"
                    return .resetNeeded(message)
                }
                assetWriter.startSession(atSourceTime: timestamp)
            }

            guard videoInput.isReadyForMoreMediaData else {
                return .dropped
            }

            guard videoInput.append(sampleBuffer) else {
                let message = assetWriter.error?.localizedDescription ?? "video append returned false"
                return .resetNeeded(message)
            }

            if startPTS == nil {
                startPTS = timestamp
                startedAt = sampleDate
            }

            latestPTS = timestamp
            latestSampleAt = sampleDate
            return .appended

        case .audio:
            guard assetWriter.status == .writing else { return .dropped }
            if let systemAudioInput, systemAudioInput.isReadyForMoreMediaData {
                _ = systemAudioInput.append(sampleBuffer)
            }
            return .appended

        case .microphone:
            guard assetWriter.status == .writing else { return .dropped }
            if let microphoneInput, microphoneInput.isReadyForMoreMediaData {
                _ = microphoneInput.append(sampleBuffer)
            }
            return .appended

        @unknown default:
            return .dropped
        }
    }

    func cancelAndDiscard() {
        if assetWriter.status == .writing || assetWriter.status == .unknown {
            assetWriter.cancelWriting()
        }

        try? FileManager.default.removeItem(at: url)
    }

    func finish() async -> SegmentInfo? {
        guard startPTS != nil, latestPTS != nil else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        finishStateQueue.sync {
            hasResumedFinishContinuation = false
        }

        videoInput.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneInput?.markAsFinished()

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + self.finishTimeout) { [weak self] in
                guard let self else { return }

                if self.assetWriter.status == .writing || self.assetWriter.status == .unknown {
                    self.assetWriter.cancelWriting()
                }

                try? FileManager.default.removeItem(at: self.url)
                self.resumeFinishContinuation(continuation, result: nil)
            }

            assetWriter.finishWriting {
                guard self.assetWriter.status == .completed,
                      let startPTS = self.startPTS,
                      let latestPTS = self.latestPTS else {
                    try? FileManager.default.removeItem(at: self.url)
                    self.resumeFinishContinuation(continuation, result: nil)
                    return
                }

                let duration = max(0, CMTimeSubtract(latestPTS, startPTS).seconds)
                let startedAt = self.startedAt ?? Date().addingTimeInterval(-duration)
                let endedAt = self.latestSampleAt ?? startedAt.addingTimeInterval(duration)

                self.resumeFinishContinuation(
                    continuation,
                    result: SegmentInfo(
                        url: self.url,
                        startedAt: startedAt,
                        endedAt: endedAt,
                        startPTS: startPTS,
                        endPTS: latestPTS,
                        duration: duration
                    )
                )
            }
        }
    }

    private func resumeFinishContinuation(
        _ continuation: CheckedContinuation<SegmentInfo?, Never>,
        result: SegmentInfo?
    ) {
        let shouldResume = finishStateQueue.sync { () -> Bool in
            guard !hasResumedFinishContinuation else { return false }
            hasResumedFinishContinuation = true
            return true
        }

        guard shouldResume else { return }
        continuation.resume(returning: result)
    }
}
