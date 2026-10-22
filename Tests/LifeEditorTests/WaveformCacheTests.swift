import Foundation
import Testing
@preconcurrency import AVFoundation
import LifeAnalysis
@testable import LifeEditor
private func waveformFile(_ url:URL,rate:Double=48000,channels:Int=2,amplitude:Float=0.8,seconds:Int=1)throws {
    let format=AVAudioFormat(standardFormatWithSampleRate:rate,channels:AVAudioChannelCount(channels))!
    let file=try AVAudioFile(forWriting:url,settings:format.settings.merging([AVLinearPCMIsNonInterleaved:false]){_,new in new})
    let count=Int(rate)*seconds,buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(count))!;buffer.frameLength=AVAudioFrameCount(count)
    for channel in 0..<channels {for index in 0..<count {buffer.floatChannelData![channel][index]=0}}
    buffer.floatChannelData![0][12345]=amplitude
    if channels>1 {buffer.floatChannelData![1][12346] = -0.6;buffer.floatChannelData![1][40000]=0.5}
    try file.write(from:buffer)
}
@Test func nativeWaveformsRetainStereoImpulsesAndExactSampleWindow() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:root)}
    let source=root.appendingPathComponent("source.wav"),cache=root.appendingPathComponent("cache")
    try waveformFile(source);let bytes=try Data(contentsOf:source),service=WaveformCache(root:cache)
    let overview=try await service.overview(for:source)
    #expect(overview.pyramid.sampleRate == 48000);#expect(overview.pyramid.channelCount == 2);#expect(overview.pyramid.sampleCount == 48000)
    #expect(overview.pyramid.levels.last?.channels[0][0].maximum == 0.8)
    #expect(overview.pyramid.levels.last?.channels[1][0].minimum == -0.6)
    let window=try await service.samples(for:source,from:12340.0/48000,to:12350.0/48000)
    #expect(window.firstSample == 12340);#expect(window.channels[0].count == 10)
    #expect(window.channels[0][5] == 0.8);#expect(window.channels[1][6] == -0.6)
    #expect(window.channels[1][5] == 0)
    #expect(try Data(contentsOf:source) == bytes)
}
@Test func nativeWaveformCacheRebuildsCorruptionAndInvalidatesModifiedSource() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:root)}
    let source=root.appendingPathComponent("source.wav"),cache=root.appendingPathComponent("cache")
    try waveformFile(source,rate:44100,channels:1)
    try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:1000)],ofItemAtPath:source.path)
    let first=try await WaveformCache(root:cache).overview(for:source),file=cache.appendingPathComponent(first.sourceKey+".waveform")
    try Data("corrupt".utf8).write(to:file)
    let service=WaveformCache(root:cache),repaired=try await service.overview(for:source)
    #expect(repaired.pyramid == first.pyramid)
    #expect(try WaveformPyramid.decode(Data(contentsOf:file)) == first.pyramid)
    try waveformFile(source,rate:44100,channels:1,amplitude:0)
    try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:2000)],ofItemAtPath:source.path)
    let changed=try await service.overview(for:source)
    #expect(changed.sourceKey != first.sourceKey);#expect(changed.pyramid.sampleRate == 44100);#expect(changed.pyramid.channelCount == 1)
    #expect(changed.pyramid.levels.last?.channels[0][0].maximum == 0)
    let window=try await service.samples(for:source,from:0,to:0.1)
    #expect(window.channels[0].allSatisfy{$0==0})
}
@Test func nativeWaveformCancellationAndOversizedWindowLeaveOriginalIntact() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:root)}
    let source=root.appendingPathComponent("source.wav");try waveformFile(source,seconds:8)
    let bytes=try Data(contentsOf:source),service=WaveformCache(root:root.appendingPathComponent("cache"))
    let task=Task{try await service.overview(for:source)};task.cancel()
    await #expect(throws:CancellationError.self){try await task.value}
    await #expect(throws:WaveformCacheError.invalidSource){try await service.samples(for:source,from:-1,to:0)}
    await #expect(throws:WaveformCacheError.windowTooLarge){try await service.samples(for:source,from:0,to:8)}
    #expect(try Data(contentsOf:source) == bytes)
}

@Test func nativeWaveformsRemainUsableWhenDiskCacheCannotBeWritten() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:root)}
    let source=root.appendingPathComponent("source.wav"),blocked=root.appendingPathComponent("blocked-cache")
    try waveformFile(source)
    let sentinel=Data("keep".utf8);try sentinel.write(to:blocked)
    let service=WaveformCache(root:blocked),first=try await service.overview(for:source)
    let second=try await service.overview(for:source)
    #expect(first.pyramid.sampleCount==48000)
    #expect(second.pyramid==first.pyramid)
    #expect(try Data(contentsOf:blocked)==sentinel)
}
