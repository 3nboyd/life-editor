import Testing
import Foundation
@preconcurrency import AVFoundation
import LifeCore
@testable import LifeMedia

@MainActor struct AudioDSPTests {
    @Test func calibratedStereoLoudnessAndSilence() {
        var scan = AudioAccumulator(bucketSize: 2400)
        for frame in 0..<96000 {
            let value = sin(Double(frame) * 2 * .pi * 1000 / 48000) * 0.1
            scan.sample(value, value)
        }
        let result = scan.finish()
        #expect(abs(result.measurement.peakDBFS + 20) < 0.001)
        #expect(abs(result.measurement.rmsDBFS + 23.0103) < 0.001)
        #expect(abs(result.measurement.loudnessLUFS! + 20) < 0.15)
        #expect(result.measurement.sampleCount == 96000)
        #expect(result.meters.count == 40)
        var silence = AudioAccumulator(bucketSize: 2400)
        for _ in 0..<24000 { silence.sample(0, 0) }
        let quiet = silence.finish()
        #expect(quiet.measurement.peakDBFS == -.infinity)
        #expect(quiet.measurement.rmsDBFS == -.infinity)
        #expect(quiet.measurement.loudnessLUFS == -.infinity)
        #expect(quiet.meters.allSatisfy { $0.leftDBFS == -.infinity && $0.rightDBFS == -.infinity })
        var short = AudioAccumulator(bucketSize: 2400)
        for _ in 0..<100 { short.sample(0.1, 0.1) }
        #expect(short.finish().measurement.loudnessLUFS == nil)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"] == "1"))
    func nativeDSPHeadroomChannelsEQAndLimiterMatchPreviewExport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("life-dsp-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calibration = directory.appendingPathComponent("calibration.wav")
        try stereo(calibration, leftHz: 1000, rightHz: 1000, left: 0.1, right: 0.1)
        let pipeline = MediaPipeline()
        let asset = try await pipeline.probe(calibration).asset
        func document(_ settings: AudioSettings? = nil, volume: Double = 1, speed: Double = 1, pitch: Bool = true) -> ProjectDocument {
            .init(sequence: .init(settings: .init(width: 64, height: 64), tracks: [
                .init(name: "Audio", kind: .audio, clips: [.init(assetID: asset.id, duration: .init(value: 2, timescale: 1), speed: speed, preservesPitch: pitch, volume: .init(baseValue: volume), audio: settings)])
            ]), assets: [asset])
        }
        let original = document()
        let baseline = try await pipeline.measure(.init(document: original))
        #expect(abs(baseline.peakDBFS + 20) < 0.01)
        #expect(abs(baseline.rmsDBFS + 23.0103) < 0.01)
        #expect(abs(baseline.loudnessLUFS! + 20) < 0.15)
        #expect(baseline.sampleCount == 96000)
        let boosted = document(volume: 4)
        let prepared = try await pipeline.prepare(.init(document: boosted))
        var from: Float = 0, to: Float = 0
        var range = CMTimeRange.invalid
        let input = try #require(prepared.playerItem.audioMix?.inputParameters.first)
        #expect(input.getVolumeRamp(for: .zero, startVolume: &from, endVolume: &to, timeRange: &range))
        #expect(from <= 1 && to <= 1)
        let previewSamples = try await samples(prepared.playerItem.asset, mix: prepared.playerItem.audioMix)
        #expect(abs(rms(previewSamples, channel: 0) - 0.4 / sqrt(2)) < 0.001)
        let wav = directory.appendingPathComponent("boost.wav")
        try await pipeline.export(.init(document: boosted), to: wav, options: .init(format: .wav))
        let exported = try await samples(AVURLAsset(url: wav))
        #expect(exported.count == 192000 && previewSamples.count == exported.count)
        #expect(zip(previewSamples, exported).allSatisfy { abs($0 - $1) < 0.0001 })
        var automated = document()
        automated.sequence.tracks[0].clips[0].volume = .init(points: [.init(time: .zero, value: 0), .init(time: .init(value: 2, timescale: 1), value: 4)])
        let automatedMeasurement = try await pipeline.measure(.init(document: automated))
        #expect(abs(automatedMeasurement.rmsDBFS - 20 * log10(0.4 / sqrt(6.0))) < 0.02)
        var automatedLimiter = automated
        automatedLimiter.sequence.tracks[0].clips[0].audio = .init(gainDB: 12, limiterEnabled: true, limiterCeilingDB: -3)
        let automatedItem = try await pipeline.prepare(.init(document: automatedLimiter))
        let automatedSamples = try await samples(automatedItem.playerItem.asset, mix: automatedItem.playerItem.audioMix)
        let uncompressedPeak = 0.1 * pow(10.0, 12 / 20.0) * 4 * (4812.0 / 96000)
        #expect(abs(Double(automatedSamples[4812 * 2]) - uncompressedPeak) < 0.001)
        let clipping = try await pipeline.measure(.init(document: document(.init(gainDB: 12), volume: 4)))
        #expect(clipping.peakDBFS > 4)
        let clippingMeters = try await pipeline.audioMeterFrames(.init(document: document(.init(gainDB: 12), volume: 4)))
        #expect(clippingMeters.contains { $0.leftDBFS > 0 && $0.rightDBFS > 0 })
        let limited = document(.init(gainDB: 12, limiterEnabled: true, limiterCeilingDB: -3), volume: 4)
        let limitedSnapshot = ProjectSnapshot(document: try ProjectDocument.decode(limited.encoded()))
        let limitedMeasurement = try await pipeline.measure(limitedSnapshot)
        #expect(abs(limitedMeasurement.peakDBFS + 3) < 0.01)
        #expect(limitedMeasurement.sampleCount == 96000)
        let limitedItem = try await pipeline.prepare(limitedSnapshot)
        let limitedPreview = try await samples(limitedItem.playerItem.asset, mix: limitedItem.playerItem.audioMix)
        let limitedURL = directory.appendingPathComponent("limited.wav")
        try await pipeline.export(limitedSnapshot, to: limitedURL, options: .init(format: .wav))
        let limitedExport = try await samples(AVURLAsset(url: limitedURL))
        #expect(limitedExport.count == 192000)
        #expect(zip(limitedPreview, limitedExport).allSatisfy { abs($0 - $1) < 0.0001 })
        let ceiling = pow(10.0, -3 / 20.0)
        #expect(limitedPreview.allSatisfy { abs(Double($0)) <= ceiling + 0.00001 })
        // No lookahead presentation delay: the first positive sine peak is still frame12.
        #expect(abs(Double(limitedPreview[12 * 2]) - ceiling) < 0.001)
        let eq = try await pipeline.measure(.init(document: document(.init(eqMidDB: 6))))
        #expect(abs(eq.rmsDBFS - baseline.rmsDBFS - 6) < 0.1)
        let unlocked = try await pipeline.prepare(.init(document: document(volume: 2, speed: 0.5, pitch: false)))
        let retimed = try await samples(unlocked.playerItem.asset, mix: unlocked.playerItem.audioMix)
        let mono = stride(from: 9600, to: 38400, by: 2).map { retimed[$0] }
        let crossings = zip(mono, mono.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
        #expect(abs(Double(crossings) / (Double(mono.count) / 48000) - 500) < 10)
        #expect(retimed.count == 192000)

        let split = directory.appendingPathComponent("stereo.wav")
        try stereo(split, leftHz: 120, rightHz: 8000, left: 0.1, right: 0.3)
        let source = try await pipeline.probe(split).asset
        func channelDocument(_ settings: AudioSettings) -> ProjectDocument {
            .init(sequence: .init(settings: .init(width: 64, height: 64), tracks: [
                .init(name: "Channels", kind: .audio, clips: [.init(assetID: source.id, duration: .init(value: 2, timescale: 1), audio: settings)])
            ]), assets: [source])
        }
        let pan = try await pipeline.prepare(.init(document: channelDocument(.init(pan: 1, channels: .left))))
        let panned = try await samples(pan.playerItem.asset, mix: pan.playerItem.audioMix)
        #expect(rms(panned, channel: 0) < 0.0000001)
        #expect(abs(rms(panned, channel: 1) - 0.1 / sqrt(2)) < 0.001)
        let meter = try await pipeline.audioMeterFrames(.init(document: channelDocument(.init(pan: 1, channels: .left))))
        #expect(meter.allSatisfy { $0.leftDBFS < -100 && abs($0.rightDBFS + 20) < 0.01 })
        let monoRMS = sqrt(0.01 + 0.09) / (2 * sqrt(2.0))
        let channelCases: [(AudioSettings, Double)] = [(.init(channels: .right), 0.3 / sqrt(2.0)), (.init(channels: .mono), monoRMS)]
        for (settings, expected) in channelCases {
            let item = try await pipeline.prepare(.init(document: channelDocument(settings)))
            let values = try await samples(item.playerItem.asset, mix: item.playerItem.audioMix)
            #expect(abs(rms(values, channel: 0) - expected) < 0.001)
            #expect(abs(rms(values, channel: 1) - expected) < 0.001)
        }
        let eqCases: [(AudioSettings, Int, Double)] = [(.init(eqLowDB: 12), 0, 0.1 / sqrt(2.0)), (.init(eqHighDB: 12), 1, 0.3 / sqrt(2.0))]
        for (settings, channel, reference) in eqCases {
            let item = try await pipeline.prepare(.init(document: channelDocument(settings)))
            let values = try await samples(item.playerItem.asset, mix: item.playerItem.audioMix)
            #expect(rms(values, channel: channel) / reference > 1.8)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"] == "1" && ProcessInfo.processInfo.environment["LIFE_HELPER_DIRECTORY"] != nil))
    func loudnessMatchesPinnedEBUR128ReferenceIncludingGating() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("life-loudness-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("gated.wav")
        try stereo(url, leftHz: 1000, rightHz: 1000, left: 0.1, right: 0.1, seconds: 4, activeSeconds: 2)
        let pipeline = MediaPipeline()
        let asset = try await pipeline.probe(url).asset
        let document = ProjectDocument(sequence: .init(settings: .init(width: 64, height: 64), tracks: [
            .init(name: "Gated", kind: .audio, clips: [.init(assetID: asset.id, duration: .init(value: 4, timescale: 1))])
        ]), assets: [asset])
        let measurement = try await pipeline.measure(.init(document: document))
        let process = Process(), errors = Pipe()
        process.executableURL = try #require(MediaHelpers.directory).appendingPathComponent("ffmpeg")
        process.arguments = ["-nostdin", "-i", url.path, "-af", "ebur128", "-f", "null", "-"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = errors
        try process.run()
        let log = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        let summary = try #require(log.components(separatedBy: "\n").last { $0.trimmingCharacters(in: .whitespaces).hasPrefix("I:") && $0.contains("LUFS") })
        let reference = try #require(Double(summary.split(separator: " ")[1]))
        #expect(abs(try #require(measurement.loudnessLUFS) - reference) < 0.15)
        #expect(abs(measurement.rmsDBFS + 26.0206) < 0.01)
    }

    private func stereo(_ url: URL, leftHz: Double, rightHz: Double, left: Double, right: Double, seconds: Int = 2, activeSeconds: Int? = nil) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings.merging([AVLinearPCMIsNonInterleaved: false]) { _, new in new })
        let count = seconds * 48000
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        for index in 0..<count {
            let enabled = index < (activeSeconds ?? seconds) * 48000
            buffer.floatChannelData![0][index] = enabled ? Float(sin(Double(index) * 2 * .pi * leftHz / 48000) * left) : 0
            buffer.floatChannelData![1][index] = enabled ? Float(sin(Double(index) * 2 * .pi * rightHz / 48000) * right) : 0
        }
        try file.write(from: buffer)
    }
    private func samples(_ asset: AVAsset, mix: AVAudioMix? = nil) async throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: try await asset.loadTracks(withMediaType: .audio), audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false])
        output.audioMix = mix; reader.add(output)
        try #require(reader.startReading())
        var result: [Float] = []
        while let sample = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sample) {
            var values = [Float](repeating: 0, count: CMBlockBufferGetDataLength(block) / 4)
            _ = values.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!) }
            result += values
        }
        #expect(reader.status == .completed)
        return result
    }
    private func rms(_ samples: [Float], channel: Int) -> Double {
        let values = stride(from: channel, to: samples.count, by: 2).map { Double(samples[$0]) }
        return sqrt(values.reduce(0) { $0 + $1 * $1 } / Double(values.count))
    }
}
