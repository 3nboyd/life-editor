import Testing
import Foundation
@preconcurrency import AVFoundation
import LifeCore
@testable import LifeMedia

@MainActor struct AudioNormalizationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"] == "1"))
    func explicitPeakNormalizationTargetsActualClipWithoutChangingOriginals() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("life-normalization-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tone.wav")
        try tone(url, amplitude: 0.1)
        let bytes = try Data(contentsOf: url)
        let pipeline = MediaPipeline()
        let asset = try await pipeline.probe(url).asset
        let clip = Clip(assetID: asset.id, start: .init(value: 10, timescale: 1), duration: .init(value: 1, timescale: 1))
        var track = Track(name: "Muted source", kind: .audio, clips: [clip]); track.isMuted = true
        let document = ProjectDocument(sequence: .init(settings: .init(width: 64, height: 64), tracks: [track]), assets: [asset])
        let snapshot = ProjectSnapshot(document: document)
        let suggestion = try await pipeline.suggestPeakNormalization(snapshot, clipID: clip.id)
        #expect(abs(suggestion.measuredPeakDBFS + 20) < 0.001)
        #expect(abs(suggestion.resultingGainDB - 19) < 0.001)
        #expect(abs(suggestion.gainAdjustmentDB - 19) < 0.001)
        #expect(abs(suggestion.expectedPeakDBFS + 1) < 0.001)
        #expect(!suggestion.limitedByHeadroom)
        let manual = try await pipeline.suggestPeakNormalization(snapshot, clipID: clip.id, targetDBFS: -6)
        #expect(abs(manual.resultingGainDB - 14) < 0.001)
        #expect(abs(manual.expectedPeakDBFS + 6) < 0.001)
        #expect(snapshot.document == document)
        #expect(try Data(contentsOf: url) == bytes)
        var applied = document
        applied.sequence.tracks[0].isMuted = false
        applied.sequence.tracks[0].clips[0].start = .zero
        applied.sequence.tracks[0].clips[0].audio = .init(gainDB: suggestion.resultingGainDB)
        let editor = ProjectEditor(document: document)
        try editor.perform(.replace(applied)); editor.undo(); #expect(editor.document == document); editor.redo()
        let measurement = try await pipeline.measure(editor.snapshot)
        #expect(abs(measurement.peakDBFS + 1) < 0.002)
        let output = directory.appendingPathComponent("normalized.wav")
        try await pipeline.export(editor.snapshot, to: output, options: .init(format: .wav))
        let renderedAsset = try await pipeline.probe(output).asset
        var reopened = applied
        reopened.assets = [renderedAsset]; reopened.sequence.tracks[0].clips[0].assetID = renderedAsset.id
        reopened.sequence.tracks[0].clips[0].audio = nil
        #expect(abs(try await pipeline.measure(.init(document: reopened)).peakDBFS + 1) < 0.01)
        #expect(try Data(contentsOf: url) == bytes)

        var limited = applied
        limited.sequence.tracks[0].clips[0].audio = .init(gainDB: 24, limiterEnabled: true, limiterCeilingDB: -0.1)
        let limitedSuggestion = try await pipeline.suggestPeakNormalization(.init(document: limited), clipID: clip.id)
        #expect(abs(limitedSuggestion.measuredPeakDBFS + 0.1) < 0.01)
        #expect(abs(limitedSuggestion.resultingGainDB - 19) < 0.01)
        let unchanged = try await pipeline.suggestPeakNormalization(.init(document: limited), clipID: clip.id, targetDBFS: -0.1)
        #expect(unchanged.gainAdjustmentDB == 0 && unchanged.resultingGainDB == 24)
        limited.sequence.tracks[0].clips[0].audio!.gainDB = limitedSuggestion.resultingGainDB
        #expect(abs(try await pipeline.measure(.init(document: limited)).peakDBFS + 1) < 0.01)
        limited.sequence.tracks[0].clips[0].audio!.limiterCeilingDB = -3
        do { _ = try await pipeline.suggestPeakNormalization(.init(document: limited), clipID: clip.id); Issue.record("Target above limiter ceiling must be explained") }
        catch AudioNormalizationError.limiterCeiling { }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"] == "1"))
    func silenceAndHeadroomAreExplicit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("life-normalization-limits-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pipeline = MediaPipeline()
        for (name, amplitude) in [("silent", 0.0), ("tiny", 0.000001)] {
            let url = directory.appendingPathComponent(name + ".wav")
            try tone(url, amplitude: amplitude)
            let asset = try await pipeline.probe(url).asset
            let clip = Clip(assetID: asset.id, duration: .init(value: 1, timescale: 1))
            let document = ProjectDocument(sequence: .init(settings: .init(width: 64, height: 64), tracks: [.init(name: name, kind: .audio, clips: [clip])]), assets: [asset])
            if amplitude == 0 {
                do { _ = try await pipeline.suggestPeakNormalization(.init(document: document), clipID: clip.id); Issue.record("Silence cannot normalize") }
                catch AudioNormalizationError.silentClip { }
            } else {
                let suggestion = try await pipeline.suggestPeakNormalization(.init(document: document), clipID: clip.id)
                #expect(suggestion.limitedByHeadroom)
                #expect(suggestion.resultingGainDB == 24)
                #expect(abs(suggestion.expectedPeakDBFS + 96) < 0.01)
                var applied = document
                applied.sequence.tracks[0].clips[0].audio = .init(gainDB: suggestion.resultingGainDB)
                #expect(abs(try await pipeline.measure(.init(document: applied)).peakDBFS - suggestion.expectedPeakDBFS) < 0.01)
            }
        }
    }
    @Test func invalidTargetsAreRejectedBeforeMediaAccess() async throws {
        for target in [Double.nan, Double.infinity, 1, -97] {
            do { _ = try await MediaPipeline().suggestPeakNormalization(.init(document: .init()), clipID: UUID(), targetDBFS: target); Issue.record("Invalid target must fail") }
            catch AudioNormalizationError.invalidTarget { }
        }
    }
    private func tone(_ url: URL, amplitude: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings.merging([AVLinearPCMIsNonInterleaved: false]) { _, new in new })
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
        buffer.frameLength = 48000
        for index in 0..<48000 {
            let value = Float(sin(Double(index) * 2 * .pi * 1000 / 48000) * amplitude)
            buffer.floatChannelData![0][index] = value; buffer.floatChannelData![1][index] = value
        }
        try file.write(from: buffer)
    }
}
