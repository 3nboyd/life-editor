import Testing
import AppKit
import AVFoundation
import LifeCore
@testable import LifeEditor
@MainActor @Test func playbackMeterVisibilitySeekAndMixChangesNeverPublishStaleState()async throws{
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:directory)}
    let url=directory.appendingPathComponent("tone.wav"),format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!,buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:48000)!
    buffer.frameLength=48000;for i in 0..<48000{buffer.floatChannelData![0][i]=0.5;buffer.floatChannelData![1][i]=0.25}
    do{let file=try AVAudioFile(forWriting:url,settings:format.settings);try file.write(from:buffer)}
    let store=EditorStore(),item=AVPlayerItem(url:url);store.document=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Title",kind:.title,clips:[Clip(duration:.init(value:1,timescale:1),title:TitleContent(text:"Meter"))])]))
    store.player.replaceCurrentItem(with:item);#expect(!store.playbackMeterVisible && store.playbackMeter==nil)
    store.setPlaybackMeterVisible(true)
    func waitFor(_ condition:()->Bool)async throws{let deadline=ContinuousClock.now.advanced(by:.seconds(4));while !condition(){try #require(ContinuousClock.now<deadline);try await Task.sleep(for:.milliseconds(10))}}
    try await waitFor{store.playbackMeter != nil};#expect(abs((store.playbackMeter?.frame.leftDBFS ?? 0)+6.0206)<0.03)
    for i in 1...8{store.seek(Double(i)/10)}
    try await waitFor{store.playbackMeter?.frame.time==RationalTime(value:4,timescale:5)}
    let mix=AVMutableAudioMix(),input=AVMutableAudioMixInputParameters();input.trackID=try #require(try await item.asset.loadTracks(withMediaType:.audio).first).trackID;input.setVolume(0,at:.zero);mix.inputParameters=[input];item.audioMix=mix
    try await waitFor{store.playbackMeter?.frame.leftDBFS == -.infinity}
    store.setPlaybackMeterVisible(false);#expect(store.playbackMeter==nil && !store.playbackMeterVisible)
    store.player.replaceCurrentItem(with:nil)
}
