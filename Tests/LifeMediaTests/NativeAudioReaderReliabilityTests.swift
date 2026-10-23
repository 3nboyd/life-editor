import Foundation
import Testing
@preconcurrency import AVFoundation
import LifeCore
@testable import LifeMedia

private actor ReaderHeartbeat {
    var ticks = 0
    func tick() { ticks += 1 }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"] == "1"))
func concurrentColdAudioReadersKeepExactFramesAndAllowCancellation() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("life-reader-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("original.wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96000)!
    buffer.frameLength = 96000
    for frame in 0..<96000 {
        buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 48000)) * 0.25
        buffer.floatChannelData![1][frame] = buffer.floatChannelData![0][frame]
    }
    do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
    let original = try Data(contentsOf: url)
    let heartbeat = ReaderHeartbeat()
    let pulse = Task {
        while !Task.isCancelled {
            await heartbeat.tick()
            try await Task.sleep(for: .milliseconds(1))
        }
    }
    defer { pulse.cancel() }
    let outputs = try await withThrowingTaskGroup(of: URL.self) { group in
        for index in 0..<8 {
            group.addTask {
                let clip = Clip(duration: .init(value: 1, timescale: 1),
                                sourceStart: .init(value: Int64(index), timescale: 48000), speed: 0.5,
                                audio: AudioSettings(gainDB: Double(index + 1)))
                return try await AudioProcessing.prepare(asset: AVURLAsset(url: url), clip: clip).url
            }
        }
        var urls: [URL] = []
        for try await output in group { urls.append(output) }
        return urls
    }
    defer { for output in outputs { try? FileManager.default.removeItem(at: output) } }
    #expect(outputs.count == 8)
    for output in outputs {
        let file = try AVAudioFile(forReading: output)
        #expect(file.length == 48000)
        #expect(file.processingFormat.channelCount == 2)
        #expect(file.processingFormat.sampleRate == 48000)
    }
    #expect(await heartbeat.ticks > 1)
    let cancelled = Task {
        let clip = Clip(duration: .init(value: 1, timescale: 1), speed: 0.75)
        return try await AudioRetime.render(asset: AVURLAsset(url: url), clip: clip)
    }
    cancelled.cancel()
    do { _ = try await cancelled.value; Issue.record("Cancelled reader unexpectedly succeeded") }
    catch is CancellationError {} catch { throw error }
    #expect(try Data(contentsOf: url) == original)
}
