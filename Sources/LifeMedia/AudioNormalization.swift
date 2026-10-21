import Foundation
@preconcurrency import AVFoundation
import LifeCore

public enum AudioNormalizationError: LocalizedError {
    case silentClip, noAudio, audioDisabled, invalidTarget, limiterCeiling(Double)
    public var errorDescription: String? {
        switch self {
        case .silentClip: "This clip is silent. There is no audible peak to normalize."
        case .noAudio: "Select a clip with an audio recording."
        case .audioDisabled: "Select the detached audio clip to normalize its level."
        case .invalidTarget: "Choose a peak target between −96 and 0 dBFS."
        case .limiterCeiling(let ceiling): "Raise or disable the clip limiter before choosing a target above \(String(format: "%.1f", ceiling)) dBFS."
        }
    }
}

/// An explicit edit proposal. The document and all source files remain unchanged.
public struct PeakNormalizationSuggestion: Equatable, Sendable {
    public let clipID: UUID
    public let measuredPeakDBFS: Double
    public let targetDBFS: Double
    public let gainAdjustmentDB: Double
    public let resultingGainDB: Double
    public let expectedPeakDBFS: Double
    public let limitedByHeadroom: Bool
}

extension MediaPipeline {
    /// Measures only this clip's source/settings/envelope, independent of its
    /// timeline position and track mute. Caller must explicitly apply the returned
    /// static gain through an editing command; export never normalizes implicitly.
    public func suggestPeakNormalization(_ snapshot: ProjectSnapshot, clipID: UUID, targetDBFS: Double = -1,
                                         progress: (@MainActor @Sendable (Double) -> Void)? = nil) async throws -> PeakNormalizationSuggestion {
        guard targetDBFS.isFinite, (-96...0).contains(targetDBFS) else { throw AudioNormalizationError.invalidTarget }
        try snapshot.document.validate()
        guard var clip = snapshot.document.sequence.tracks.flatMap(\.clips).first(where: { $0.id == clipID }) else { throw DocumentError.clipNotFound }
        guard clip.audioEnabled ?? true else { throw AudioNormalizationError.audioDisabled }
        guard let assetID = clip.assetID, let asset = snapshot.document.assets.first(where: { $0.id == assetID }), asset.kind != .image else { throw AudioNormalizationError.noAudio }
        let settings = clip.audio ?? AudioSettings()
        if settings.limiterEnabled, targetDBFS > settings.limiterCeilingDB { throw AudioNormalizationError.limiterCeiling(settings.limiterCeilingDB) }
        let source = AVURLAsset(url: asset.preparedURL ?? asset.url)
        guard !(try await source.loadTracks(withMediaType: .audio)).isEmpty else { throw AudioNormalizationError.noAudio }
        clip.start = .zero
        clip.title = nil; clip.graphic = nil; clip.effects = nil; clip.visual = nil
        let isolated = ProjectDocument(sequence: .init(settings: .init(width: 64, height: 64), tracks: [
            .init(name: clip.name, kind: .audio, clips: [clip])
        ]), assets: [asset])
        let firstProgress: (@MainActor @Sendable (Double) -> Void)?
        if settings.limiterEnabled { firstProgress = { value in progress?(value * 0.5) } }
        else { firstProgress = progress }
        let measured = try await measure(.init(document: isolated), progress: firstProgress)
        guard measured.peakDBFS.isFinite else { throw AudioNormalizationError.silentClip }
        if Swift.abs(targetDBFS - measured.peakDBFS) < 0.000001 {
            progress?(1)
            return .init(clipID: clipID, measuredPeakDBFS: measured.peakDBFS, targetDBFS: targetDBFS,
                         gainAdjustmentDB: 0, resultingGainDB: settings.gainDB,
                         expectedPeakDBFS: measured.peakDBFS, limitedByHeadroom: false)
        }
        var referencePeak = measured.peakDBFS
        if settings.limiterEnabled {
            // Gain precedes the limiter. Measuring the compressed output alone
            // cannot tell how much reduction is needed to get below its ceiling.
            var unlimited = isolated
            var audio = settings; audio.limiterEnabled = false
            unlimited.sequence.tracks[0].clips[0].audio = audio
            referencePeak = try await measure(.init(document: unlimited), progress: { value in progress?(0.5 + value * 0.5) }).peakDBFS
        }
        guard referencePeak.isFinite else { throw AudioNormalizationError.silentClip }
        let requested: Double = targetDBFS - referencePeak
        let resultingGain: Double = max(-96, min(24, settings.gainDB + requested))
        let adjustment: Double = resultingGain - settings.gainDB
        let predicted = referencePeak + adjustment
        return .init(clipID: clipID, measuredPeakDBFS: measured.peakDBFS, targetDBFS: targetDBFS,
                     gainAdjustmentDB: adjustment, resultingGainDB: resultingGain,
                     expectedPeakDBFS: settings.limiterEnabled ? min(settings.limiterCeilingDB, predicted) : predicted,
                     limitedByHeadroom: Swift.abs(adjustment - requested) > 0.000001)
    }
}
