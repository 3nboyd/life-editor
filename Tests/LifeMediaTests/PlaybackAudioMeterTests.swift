import Testing
@preconcurrency import AVFoundation
import LifeCore
@testable import LifeMedia

private func meterTone(_ url:URL,left:Float,right:Float)throws{
    let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!,buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:48000)!
    buffer.frameLength=48000
    for index in 0..<48000{let wave=Float(sin(Double(index)*2 * .pi*1000/48000));buffer.floatChannelData![0][index]=wave*left;buffer.floatChannelData![1][index]=wave*right}
    let file=try AVAudioFile(forWriting:url,settings:format.settings);try file.write(from:buffer)
}
@MainActor private func meterItem(_ urls:[URL],at offset:Double=0,volumes:[Float]=[])async throws->AVPlayerItem{
    let composition=AVMutableComposition();var inputs:[AVAudioMixInputParameters]=[]
    for (index,url) in urls.enumerated(){
        let asset=AVURLAsset(url:url),source=try #require(try await asset.loadTracks(withMediaType:.audio).first),track=try #require(composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid))
        try track.insertTimeRange(CMTimeRange(start:.zero,duration:CMTime(seconds:1,preferredTimescale:48000)),of:source,at:CMTime(seconds:offset,preferredTimescale:48000))
        let input=AVMutableAudioMixInputParameters(track:track);input.setVolume(volumes.indices.contains(index) ? volumes[index]:1,at:.zero);inputs.append(input)
    }
    let item=AVPlayerItem(asset:composition),mix=AVMutableAudioMix();mix.inputParameters=inputs;item.audioMix=mix;return item
}
@MainActor @Test func liveMixMeterMeasuresSummedPhaseStereoAndClippingWithoutLimiting()async throws{
    let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
    let positive=dir.appendingPathComponent("positive.wav"),negative=dir.appendingPathComponent("negative.wav");try meterTone(positive,left:0.75,right:0.25);try meterTone(negative,left:-0.75,right:-0.25)
    let sum=try await PlaybackAudioMeter.read(PlaybackMeterSource(item:meterItem([positive,positive])),at:.init(value:1,timescale:2))
    #expect(abs(sum.frame.leftDBFS-20*log10(1.5))<0.02);#expect(abs(sum.frame.rightDBFS-20*log10(0.5))<0.02)
    #expect(sum.frame.leftDBFS>0);#expect(sum.sampleCount<=4800 && sum.sampleCount>0)
    let cancellation=try await PlaybackAudioMeter.read(PlaybackMeterSource(item:meterItem([positive,negative])),at:.init(value:1,timescale:2))
    #expect(cancellation.frame.leftDBFS < -100);#expect(cancellation.frame.rightDBFS < -100)
    print("Live mix meter current-host window seconds:",sum.elapsedSeconds,"samples:",sum.sampleCount)
}
@MainActor @Test func liveMixMeterWindowIsBoundedAtHourPositionAndTracksPausedAuditionMix()async throws{
    let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
    let url=dir.appendingPathComponent("tone.wav");try meterTone(url,left:0.5,right:0.25)
    let item=try await meterItem([url],at:3600),original=PlaybackMeterSource(item:item)
    let atHour=try await PlaybackAudioMeter.read(original,at:.init(value:7201,timescale:2))
    #expect(abs(atHour.frame.leftDBFS+6.0206)<0.02);#expect(atHour.sampleCount<=4800)
    let gap=try await PlaybackAudioMeter.read(original,at:.init(value:120,timescale:1));#expect(gap.frame.leftDBFS == -.infinity)
    let mix=AVMutableAudioMix(),input=AVMutableAudioMixInputParameters();input.trackID=try #require(try await item.asset.loadTracks(withMediaType:.audio).first).trackID;input.setVolume(0,at:.zero);mix.inputParameters=[input];item.audioMix=mix
    #expect(!original.matches(item));let audition=PlaybackMeterSource(item:item);#expect(audition.matches(item))
    let quiet=try await PlaybackAudioMeter.read(audition,at:.init(value:7201,timescale:2));#expect(quiet.frame.leftDBFS == -.infinity)
    let old=try await PlaybackAudioMeter.read(original,at:.init(value:7201,timescale:2));#expect(abs(old.frame.leftDBFS-atHour.frame.leftDBFS)<0.001)
    do{_ = try await PlaybackAudioMeter.read(audition,at:.init(value:1,timescale:4_000_000_000));Issue.record("Unsupported meter timescale accepted")}catch MediaError.invalidRange{}catch{Issue.record("Unexpected invalid time error: \(error)")}
    let cancelled=Task{try await PlaybackAudioMeter.read(audition,at:.zero)};cancelled.cancel()
    do{_ = try await cancelled.value;Issue.record("Cancelled meter decoded")}catch is CancellationError{}catch{Issue.record("Unexpected cancellation: \(error)")}
}
@MainActor @Test func liveMixMeterUsesPreparedPanGainAndSharedVolumeEnvelope()async throws{
    let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
    let url=dir.appendingPathComponent("tone.wav");try meterTone(url,left:0.5,right:0.5)
    let asset=MediaAsset(url:url,kind:.audio,duration:.init(value:1,timescale:1)),clip=Clip(assetID:asset.id,duration:asset.duration,volume:.init(points:[.init(time:.zero,value:0),.init(time:asset.duration,value:1)]),audio:.init(gainDB:6,pan:-1))
    let document=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Music",kind:.audio,clips:[clip])]),assets:[asset]),prepared=try await MediaPipeline().prepare(.init(document:document)),source=PlaybackMeterSource(item:prepared.playerItem)
    let early=try await PlaybackAudioMeter.read(source,at:.init(value:1,timescale:4)),late=try await PlaybackAudioMeter.read(source,at:.init(value:3,timescale:4))
    #expect(late.frame.leftDBFS>early.frame.leftDBFS+6);#expect(late.frame.rightDBFS < -90)
    #expect(late.sampleCount<=4800)
}
