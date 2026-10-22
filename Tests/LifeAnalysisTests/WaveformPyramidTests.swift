import Foundation
import Testing
@testable import LifeAnalysis
@Test func waveformPyramidPreservesChannelPolarityAcrossStreamingBuckets() throws {
    var builder=try WaveformPyramidBuilder(channelCount:2,sampleRate:48000,baseSamplesPerBin:4)
    try builder.append(interleaved:[0,0,1,0,0,-0.5])
    try builder.append(interleaved:[0,0,-0.25,0.75,0,0,0,0,0,0,0.1,0.2])
    let result=try builder.finish()
    #expect(result.sampleCount == 9);#expect(result.channelCount == 2)
    #expect(result.levels[0].channels[0][0] == WaveformBin(minimum:0,maximum:1))
    #expect(result.levels[0].channels[1][0] == WaveformBin(minimum:-0.5,maximum:0))
    #expect(result.levels[0].channels[0][1].minimum == -0.25)
    #expect(result.levels.last?.channels[1][0].maximum == 0.75)
    #expect(result.level(samplesPerPixel:8)?.samplesPerBin == 8)
    #expect(try WaveformPyramid.decode(result.encoded()) == result)
}
@Test func waveformBinaryCacheDetectsCorruptionAndRejectsMalformedFormats() throws {
    var builder=try WaveformPyramidBuilder(channelCount:1,sampleRate:44100,baseSamplesPerBin:256)
    try builder.appendSilence(frames:1000)
    let silence=try builder.finish()
    #expect(silence.levels.flatMap(\.channels).flatMap{$0}.allSatisfy{$0.minimum==0 && $0.maximum==0})
    var corrupted=try silence.encoded();corrupted[40] ^= 1
    #expect(throws:WaveformError.invalidCache){try WaveformPyramid.decode(corrupted)}
    #expect(throws:WaveformError.invalidCache){try WaveformPyramid.decode(Data([1,2,3]))}
    #expect(throws:WaveformError.invalidFormat){try WaveformPyramidBuilder(channelCount:0,sampleRate:48000)}
    #expect(throws:WaveformError.invalidFormat){try WaveformPyramidBuilder(channelCount:2,sampleRate:.infinity)}
    var stereo=try WaveformPyramidBuilder(channelCount:2,sampleRate:48000)
    #expect(throws:WaveformError.invalidFormat){try stereo.append(interleaved:[1])}
}
@Test func waveformCancellationStopsBeforeBuildingSilentRecording() async throws {
    let task=Task {var builder=try WaveformPyramidBuilder(channelCount:2,sampleRate:48000);try Task.checkCancellation();try builder.appendSilence(frames:172800000);return try builder.finish()}
    task.cancel()
    await #expect(throws:CancellationError.self){try await task.value}
}
