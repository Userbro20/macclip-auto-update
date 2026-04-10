import AVFoundation
import Foundation
@preconcurrency import Speech

private enum VoiceCommandError: LocalizedError {
    case noMicrophoneAvailable
    case unableToAddInput(String)
    case unableToAddOutput

    var errorDescription: String? {
        switch self {
        case .noMicrophoneAvailable:
            return "No microphone input is available."
        case .unableToAddInput(let deviceName):
            return "Could not use \(deviceName) for voice commands."
        case .unableToAddOutput:
            return "Could not start the voice command audio pipeline."
        }
    }
}

final class VoiceCommandManager: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let sessionQueue = DispatchQueue(label: "MacClipper.voice-command.session")
    private let captureSession = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let triggerCommands = [
        "Mac clip that",
        "MacClip that"
    ]
    private let normalizedTriggerCommands = [
        "mac clip that",
        "macclip that"
    ]
    private let minimumRecognitionInterval: TimeInterval = 2
    private let recognitionRestartDelay: TimeInterval = 0.35

    var onClipCommand: ((String) -> Void)?

    private var preferredMicrophoneDeviceID: String?
    private var currentInput: AVCaptureDeviceInput?
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var pendingRestartWorkItem: DispatchWorkItem?
    private var requestedStart = false
    private var isListening = false
    private var lastRecognitionAt: Date?
    private var recognitionGeneration = 0

    private lazy var speechRecognizer: SFSpeechRecognizer? = {
        SFSpeechRecognizer(locale: Locale(identifier: "en-US")) ?? SFSpeechRecognizer()
    }()

    private let captureAudioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false
    ]

    func setPreferredMicrophoneDeviceID(_ deviceID: String?) {
        let normalizedDeviceID = Self.normalizedMicrophoneDeviceID(deviceID)

        sessionQueue.async {
            guard self.preferredMicrophoneDeviceID != normalizedDeviceID else { return }
            self.preferredMicrophoneDeviceID = normalizedDeviceID

            guard self.requestedStart else { return }
            self.restartListeningLocked(reason: "microphone selection changed")
        }
    }

    func start() {
        sessionQueue.async {
            self.requestedStart = true
        }

        Task { [weak self] in
            guard let self else { return }

            let microphoneAuthorized = await Self.ensureMicrophoneAuthorization()
            let speechAuthorized = await Self.ensureSpeechAuthorization()

            self.sessionQueue.async {
                guard self.requestedStart else { return }

                guard microphoneAuthorized else {
                    AppLogger.shared.log("Voice", "voice command listener blocked: microphone permission not granted")
                    return
                }

                guard speechAuthorized else {
                    AppLogger.shared.log("Voice", "voice command listener blocked: speech recognition permission not granted")
                    return
                }

                self.beginListeningLocked()
            }
        }
    }

    func stop() {
        sessionQueue.async {
            self.requestedStart = false
            self.pendingRestartWorkItem?.cancel()
            self.pendingRestartWorkItem = nil
            self.stopListeningLocked(reason: "stopped")
        }
    }

    private func beginListeningLocked() {
        pendingRestartWorkItem?.cancel()
        pendingRestartWorkItem = nil

        guard let speechRecognizer else {
            AppLogger.shared.log("Voice", "voice command listener unavailable: speech recognizer not available")
            return
        }

        if !speechRecognizer.isAvailable && !speechRecognizer.supportsOnDeviceRecognition {
            AppLogger.shared.log("Voice", "voice command listener waiting: speech recognizer unavailable")
            scheduleRestartLocked(reason: "speech recognizer unavailable")
            return
        }

        do {
            try configureCaptureSessionLocked()
        } catch {
            AppLogger.shared.log("Voice", "voice command listener failed to configure message=\(error.localizedDescription)")
            scheduleRestartLocked(reason: "audio pipeline unavailable")
            return
        }

        startRecognitionTaskLocked(with: speechRecognizer)

        if !captureSession.isRunning {
            captureSession.startRunning()
        }

        guard captureSession.isRunning else {
            stopRecognitionTaskLocked()
            AppLogger.shared.log("Voice", "voice command listener failed to start capture session")
            scheduleRestartLocked(reason: "capture session failed to start")
            return
        }

        isListening = true
        AppLogger.shared.log(
            "Voice",
            "voice command listener started phrase=Mac clip that microphone=\(activeMicrophoneDescriptionLocked())"
        )
    }

    private func stopListeningLocked(reason: String) {
        let wasListening = isListening
        tearDownListeningLocked()

        if wasListening {
            AppLogger.shared.log("Voice", "voice command listener stopped reason=\(reason)")
        }
    }

    private func restartListeningLocked(reason: String) {
        AppLogger.shared.log("Voice", "voice command listener restarting reason=\(reason)")
        tearDownListeningLocked()

        guard requestedStart else { return }
        beginListeningLocked()
    }

    private func tearDownListeningLocked() {
        stopRecognitionTaskLocked()

        if captureSession.isRunning {
            captureSession.stopRunning()
        }

        captureSession.beginConfiguration()
        if let currentInput {
            captureSession.removeInput(currentInput)
            self.currentInput = nil
        }
        if captureSession.outputs.contains(where: { $0 === audioOutput }) {
            captureSession.removeOutput(audioOutput)
        }
        captureSession.commitConfiguration()

        isListening = false
    }

    private func configureCaptureSessionLocked() throws {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }

        captureSession.beginConfiguration()

        if let currentInput {
            captureSession.removeInput(currentInput)
            self.currentInput = nil
        }
        if captureSession.outputs.contains(where: { $0 === audioOutput }) {
            captureSession.removeOutput(audioOutput)
        }

        audioOutput.audioSettings = captureAudioSettings
        audioOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        guard captureSession.canAddOutput(audioOutput) else {
            captureSession.commitConfiguration()
            throw VoiceCommandError.unableToAddOutput
        }
        captureSession.addOutput(audioOutput)

        guard let microphone = preferredMicrophoneLocked() else {
            captureSession.commitConfiguration()
            throw VoiceCommandError.noMicrophoneAvailable
        }

        let input = try AVCaptureDeviceInput(device: microphone)
        guard captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            throw VoiceCommandError.unableToAddInput(microphone.localizedName)
        }

        captureSession.addInput(input)
        currentInput = input
        captureSession.commitConfiguration()
    }

    private func startRecognitionTaskLocked(with speechRecognizer: SFSpeechRecognizer) {
        stopRecognitionTaskLocked()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = triggerCommands
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        speechRequest = request
        recognitionGeneration += 1
        let generation = recognitionGeneration

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let manager = self else { return }

            let transcript = result?.bestTranscription.formattedString ?? ""
            let isFinal = result?.isFinal ?? false
            let errorMessage = error?.localizedDescription

            manager.sessionQueue.async {
                manager.handleRecognitionUpdate(
                    transcript: transcript,
                    isFinal: isFinal,
                    errorMessage: errorMessage,
                    generation: generation
                )
            }
        }
    }

    private func stopRecognitionTaskLocked() {
        recognitionGeneration += 1
        speechRequest?.endAudio()
        speechRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func handleRecognitionUpdate(
        transcript: String,
        isFinal: Bool,
        errorMessage: String?,
        generation: Int
    ) {
        guard generation == recognitionGeneration else { return }

        if let errorMessage {
            AppLogger.shared.log("Voice", "voice recognition error message=\(errorMessage)")
            scheduleRestartLocked(reason: "recognizer error")
            return
        }

        let normalizedTranscript = Self.normalizedTranscript(transcript)

        if let matchedCommand = matchedTriggerCommand(in: normalizedTranscript) {
            let now = Date()
            if let lastRecognitionAt, now.timeIntervalSince(lastRecognitionAt) < minimumRecognitionInterval {
                AppLogger.shared.log("Voice", "voice command ignored duplicate=\(matchedCommand)")
            } else {
                lastRecognitionAt = now
                AppLogger.shared.log("Voice", "voice command recognized=\(matchedCommand)")
                onClipCommand?(matchedCommand)
            }

            restartRecognitionTaskLocked(reason: "command matched")
            return
        }

        if isFinal {
            restartRecognitionTaskLocked(reason: "final result")
        }
    }

    private func restartRecognitionTaskLocked(reason: String) {
        guard requestedStart else { return }

        guard captureSession.isRunning, let speechRecognizer else {
            scheduleRestartLocked(reason: reason)
            return
        }

        AppLogger.shared.log("Voice", "voice recognition pipeline restarting reason=\(reason)")
        startRecognitionTaskLocked(with: speechRecognizer)
    }

    private func scheduleRestartLocked(reason: String) {
        guard requestedStart else { return }

        pendingRestartWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.requestedStart else { return }
            self.restartListeningLocked(reason: reason)
        }

        pendingRestartWorkItem = workItem
        sessionQueue.asyncAfter(deadline: .now() + recognitionRestartDelay, execute: workItem)
    }

    private func preferredMicrophoneLocked() -> AVCaptureDevice? {
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified).devices

        if let preferredMicrophoneDeviceID,
           let preferredDevice = devices.first(where: { $0.uniqueID == preferredMicrophoneDeviceID }) {
            return preferredDevice
        }

        if let preferredMicrophoneDeviceID {
            AppLogger.shared.log(
                "Voice",
                "selected microphone unavailable id=\(preferredMicrophoneDeviceID); falling back to system default"
            )
        }

        return AVCaptureDevice.default(for: .audio) ?? devices.first
    }

    private func activeMicrophoneDescriptionLocked() -> String {
        currentInput?.device.localizedName ?? "System Default"
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard requestedStart, isListening else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return }
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        guard CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) != nil else { return }
        speechRequest?.appendAudioSampleBuffer(sampleBuffer)
    }

    private func matchedTriggerCommand(in normalizedTranscript: String) -> String? {
        for (index, normalizedCommand) in normalizedTriggerCommands.enumerated() {
            if normalizedTranscript.contains(normalizedCommand) {
                return triggerCommands[index]
            }
        }

        return nil
    }

    private static func normalizedTranscript(_ transcript: String) -> String {
        let folded = transcript
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        let sanitized = folded.unicodeScalars.map { scalar -> String in
            if CharacterSet.alphanumerics.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return String(scalar)
            }
            return " "
        }
        .joined()

        return sanitized
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func normalizedMicrophoneDeviceID(_ deviceID: String?) -> String? {
        guard let trimmed = deviceID?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private static func ensureMicrophoneAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private static func ensureSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}