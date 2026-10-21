import Foundation
@preconcurrency import Speech
import AVFoundation
import LifeCore

enum LocalTranscriptionError: Error, Equatable, LocalizedError {
    case unsupportedLocale, unavailable, permissionDenied, invalidSource, sourceTooLong, timedOut, busy, missingUsageDescription, cancelled
    case recognitionFailed(String)
    var errorDescription: String? {
        switch self {
        case .unsupportedLocale: "On-device transcription is unavailable for this language. Use manual captions or SRT."
        case .unavailable: "On-device speech recognition is unavailable. Use manual captions or SRT."
        case .permissionDenied: "Speech recognition permission is unavailable. Use manual captions or SRT."
        case .invalidSource: "Choose a readable local audio or video recording."
        case .sourceTooLong: "Local transcription supports recordings up to 60 seconds per request."
        case .timedOut: "Local transcription timed out. Try a shorter recording."
        case .busy: "A transcription is already running."
        case .missingUsageDescription: "This build does not include speech permission information. Use manual captions or SRT."
        case .cancelled: "Transcription cancelled."
        case .recognitionFailed(let detail): "Local transcription failed: \(detail)"
        }
    }
}

/// Opt-in Apple Speech transcription. Never creates a recognition request permitting server processing.
@MainActor final class LocalTranscription {
    nonisolated static let maximumSourceDuration: TimeInterval = 60
    nonisolated static let timeout: TimeInterval = 90
    private(set) var isRunning=false
    private var recognitionTask: SFSpeechRecognitionTask?
    private var resultContinuation: CheckedContinuation<[CaptionCue], any Error>?
    private var authorizationContinuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>?
    private var timeoutTask: Task<Void,Never>?
    private var pendingFailure: LocalTranscriptionError?
    private var sessionID: UUID?

    static func supports(locale: Locale) -> Bool {
        guard let recognizer=SFSpeechRecognizer(locale:locale) else { return false }
        return permitsLocalRecognition(onDeviceSupported:recognizer.supportsOnDeviceRecognition,isAvailable:recognizer.isAvailable)
    }
    nonisolated static func permitsLocalRecognition(onDeviceSupported: Bool, isAvailable: Bool) -> Bool { onDeviceSupported && isAvailable }
    static func makeRequest(url: URL) -> SFSpeechURLRecognitionRequest {
        let request=SFSpeechURLRecognitionRequest(url:url)
        request.requiresOnDeviceRecognition=true
        request.shouldReportPartialResults=false
        request.taskHint = .dictation
        return request
    }
    func transcribe(url: URL, locale: Locale = .current) async throws -> [CaptionCue] {
        guard !isRunning else { throw LocalTranscriptionError.busy }
        guard url.isFileURL, FileManager.default.isReadableFile(atPath:url.path) else { throw LocalTranscriptionError.invalidSource }
        guard let recognizer=SFSpeechRecognizer(locale:locale), recognizer.supportsOnDeviceRecognition else { throw LocalTranscriptionError.unsupportedLocale }
        guard recognizer.isAvailable else { throw LocalTranscriptionError.unavailable }
        // Avoid the OS terminating unsigned/development executables without a purpose string.
        guard let usage=Bundle.main.object(forInfoDictionaryKey:"NSSpeechRecognitionUsageDescription") as? String, !usage.isEmpty else { throw LocalTranscriptionError.missingUsageDescription }
        let id=UUID(); sessionID=id; isRunning=true; pendingFailure=nil
        timeoutTask=Task { [weak self] in
            do { try await Task.sleep(for:.seconds(Self.timeout)) } catch { return }
            guard self?.sessionID == id else { return }
            self?.fail(.timedOut)
        }
        defer {
            recognitionTask?.cancel(); recognitionTask=nil
            timeoutTask?.cancel(); timeoutTask=nil
            sessionID=nil; isRunning=false; pendingFailure=nil
        }
        return try await withTaskCancellationHandler {
            try checkCancellation()
            let duration: CMTime
            do { duration=try await AVURLAsset(url:url).load(.duration) }
            catch { try checkCancellation(); throw LocalTranscriptionError.invalidSource }
            try checkCancellation()
            guard duration.seconds.isFinite, duration.seconds > 0 else { throw LocalTranscriptionError.invalidSource }
            guard duration.seconds <= Self.maximumSourceDuration else { throw LocalTranscriptionError.sourceTooLong }
            try checkCancellation()
            let authorization=await requestAuthorization()
            try checkCancellation()
            guard authorization == .authorized else { throw LocalTranscriptionError.permissionDenied }
            // Availability can change while the system permission sheet is visible.
            guard recognizer.supportsOnDeviceRecognition else { throw LocalTranscriptionError.unsupportedLocale }
            guard recognizer.isAvailable else { throw LocalTranscriptionError.unavailable }
            let request=Self.makeRequest(url:url)
            return try await withCheckedThrowingContinuation { continuation in
                resultContinuation=continuation
                recognitionTask=recognizer.recognitionTask(with:request) { [weak self] result,error in
                    let final=result?.isFinal == true
                    let cues=final ? Self.cues(from:result!.bestTranscription.segments.map { ($0.timestamp,$0.duration,$0.substring) }) : nil
                    let detail=error?.localizedDescription
                    Task { @MainActor [weak self] in
                        guard let self, self.sessionID == id else { return }
                        if let cues { self.complete(cues) }
                        else if let detail { self.fail(.recognitionFailed(detail)) }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.sessionID == id else { return }
                self?.cancel()
            }
        }
    }
    func cancel() { guard isRunning else { return }; fail(.cancelled) }
    private func checkCancellation() throws {
        if let pendingFailure { throw pendingFailure }
        if Task.isCancelled { throw LocalTranscriptionError.cancelled }
    }
    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current=SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        let id=sessionID
        return await withCheckedContinuation { continuation in
            authorizationContinuation=continuation
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == id, let continuation=self.authorizationContinuation else { return }
                    self.authorizationContinuation=nil; continuation.resume(returning:status)
                }
            }
        }
    }
    private func complete(_ cues: [CaptionCue]) {
        guard let continuation=resultContinuation else { return }
        resultContinuation=nil
        continuation.resume(returning:cues)
    }
    private func fail(_ error: LocalTranscriptionError) {
        pendingFailure=error
        recognitionTask?.cancel()
        if let authorization=authorizationContinuation { authorizationContinuation=nil; authorization.resume(returning:.denied) }
        if let continuation=resultContinuation { resultContinuation=nil; continuation.resume(throwing:error) }
    }
    /// Source-relative word cues; no project retiming or network service participates in this conversion.
    nonisolated static func cues(from segments: [(timestamp: TimeInterval,duration: TimeInterval,text: String)]) -> [CaptionCue] {
        segments.compactMap { segment in
            guard segment.timestamp.isFinite, segment.duration.isFinite, segment.timestamp >= 0, segment.duration > 0,
                  segment.timestamp+segment.duration <= maximumSourceDuration,
                  !segment.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return nil }
            return CaptionCue(start:RationalTime(value:Int64((segment.timestamp*48000).rounded()),timescale:48000),duration:RationalTime(value:max(1,Int64((segment.duration*48000).rounded())),timescale:48000),text:segment.text)
        }
    }
}
