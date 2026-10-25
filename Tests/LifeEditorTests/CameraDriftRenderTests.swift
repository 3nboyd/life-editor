import Foundation
import Testing
@preconcurrency import AVFoundation
import CoreImage
import CryptoKit
import LifeCore
import LifeMedia
import LifeAnalysis
@testable import LifeEditor

private func driftPhase(_ message:String){
    let data=Data(("[Drift native] "+message+"\n").utf8)
    try? FileHandle.standardError.write(contentsOf:data)

}
private func driftAmplitude(_ time:Double)->Double {
    let index=Int(time),phase=time-Double(index)
    var hash=UInt64(max(0,index)) &+ 0x9e3779b97f4a7c15
    hash=(hash ^ (hash >> 30)) &* 0xbf58476d1ce4e5b9;hash=(hash ^ (hash >> 27)) &* 0x94d049bb133111eb;hash ^= hash >> 31
    guard hash%3==0 else{return 0.08}
    let center=0.15+Double((hash >> 16)%700)/1000,height=0.2+Double((hash >> 32)%800)/1000
    return 0.08+0.5*height*exp(-pow((phase-center)/0.07,2))
}
private func writeDriftTone(_ url:URL,origin:Double,slope:Double,frequency:Double)throws {
    let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!,file=try AVAudioFile(forWriting:url,settings:format.settings)
    let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:48000)!;buffer.frameLength=48000
    for second in 0..<240 {
        for frame in 0..<48000 {let t=origin+slope*(Double(second)+Double(frame)/48000);buffer.floatChannelData![0][frame]=Float(driftAmplitude(t)*sin(2 * .pi*frequency*t))}
        try file.write(from:buffer)
    }
}
private func writeDriftVideo(_ url:URL,origin:Double,slope:Double,sparse:Bool)async throws {
    let writer=try AVAssetWriter(outputURL:url,fileType:.mov),input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:64,AVVideoHeightKey:64])
    let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:64,kCVPixelBufferHeightKey as String:64])
    writer.add(input);try #require(writer.startWriting());writer.startSession(atSourceTime:.zero)
    let events=[0,(100-origin)/slope,(200-origin)/slope,239.9666667]
    let positions=sparse ? events:Array(Set(events+(0..<480).map{Double($0)/2})).sorted(),context=CIContext()
    for index in positions.indices {
        while !input.isReadyForMoreMediaData{try await Task.sleep(for:.milliseconds(1))}
        var buffer:CVPixelBuffer?;try #require(CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&buffer)==kCVReturnSuccess)
        let referenceTime=origin+slope*positions[index]
        let color=referenceTime<100 ? CIColor(red:1,green:0,blue:0):referenceTime<200 ? CIColor(red:0,green:0,blue:1):CIColor(red:0,green:1,blue:0)
        context.render(CIImage(color:color).cropped(to:CGRect(x:0,y:0,width:64,height:64)),to:buffer!)
        try #require(adaptor.append(buffer!,withPresentationTime:CMTime(seconds:positions[index],preferredTimescale:600000)))
    }
    writer.endSession(atSourceTime:CMTime(value:240,timescale:1));input.markAsFinished();await writer.finishWriting();try #require(writer.status == .completed)
}
private func mergeDriftCamera(video:URL,audio:URL,to destination:URL)async throws {
    let videoAsset=AVURLAsset(url:video),audioAsset=AVURLAsset(url:audio),composition=AVMutableComposition(),range=CMTimeRange(start:.zero,duration:CMTime(value:240,timescale:1))
    let v=try #require(try await videoAsset.loadTracks(withMediaType:.video).first),a=try #require(try await audioAsset.loadTracks(withMediaType:.audio).first)
    try composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid)!.insertTimeRange(range,of:v,at:.zero)
    try composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid)!.insertTimeRange(range,of:a,at:.zero)
    let session=try #require(AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetPassthrough));session.outputURL=destination;session.outputFileType = .mov
    await withCheckedContinuation{(continuation:CheckedContinuation<Void,Never>) in session.exportAsynchronously{continuation.resume()}}
    try #require(session.status == .completed)
}
private func driftDigest(_ url:URL)throws->SHA256.Digest {
    let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()};var hash=SHA256()
    while let data=try handle.read(upToCount:1024*1024),!data.isEmpty{hash.update(data:data)}
    return hash.finalize()
}
private func driftSamples(_ asset:AVAsset,mix:AVAudioMix?=nil,start:Double=199)async throws->[Float] {
    let tracks=try await asset.loadTracks(withMediaType:.audio),reader=try AVAssetReader(asset:asset)
    let output=AVAssetReaderAudioMixOutput(audioTracks:tracks,audioSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:48000,AVNumberOfChannelsKey:2,AVLinearPCMBitDepthKey:32,AVLinearPCMIsFloatKey:true,AVLinearPCMIsNonInterleaved:false]);output.audioMix=mix
    reader.add(output);reader.timeRange=CMTimeRange(start:CMTime(seconds:start,preferredTimescale:48000),duration:CMTime(value:2,timescale:1));try #require(reader.startReading());var values:[Float]=[];var firstPTS:Double?,lastEnd:Double?
    while let sample=output.copyNextSampleBuffer(),let block=CMSampleBufferGetDataBuffer(sample){
        let pts=CMSampleBufferGetPresentationTimeStamp(sample).seconds
        firstPTS=firstPTS ?? pts;lastEnd=pts+Double(CMSampleBufferGetNumSamples(sample))/48000
        let count=CMSampleBufferGetNumSamples(sample)*2;var chunk=[Float](repeating:0,count:count);let status=chunk.withUnsafeMutableBytes{CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:count*4,destination:$0.baseAddress!)};try #require(status==kCMBlockBufferNoErr);values+=chunk}
    try #require(reader.status == .completed);driftPhase("Read samples count=\(values.count), firstPTS=\(firstPTS ?? -1), lastEnd=\(lastEnd ?? -1), requestedStart=\(start)");return values
}
@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"]=="1"))
func driftNativePreviewExportAlignsEarlyLateAndPreservesContinuousSeparateMaster()async throws {try await runDriftNativeFixture(sparse:false)}

/// Optional long-held H.264 frame stress fixture, separate from the
/// representative bounded-gap VFR acceptance fixture.
@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_RUN_SPARSE_DRIFT_FIXTURE"]=="1"))
func driftSparseLongHeldBFrameRangeExportDiagnostic()async throws {try await runDriftNativeFixture(sparse:true)}

@MainActor private func runDriftNativeFixture(sparse:Bool)async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("life-drift-native-"+UUID().uuidString);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:directory)}
    driftPhase("Fixture path: \(directory.path); sparse=\(sparse)")
    let masterURL=directory.appendingPathComponent("master.wav"),cameraAudio=directory.appendingPathComponent("camera.wav")
    // Build long originals off the UI actor; camera audio has a different tone.
    try await Task.detached{try writeDriftTone(masterURL,origin:0,slope:1,frequency:660);try writeDriftTone(cameraAudio,origin:2,slope:0.999,frequency:440)}.value
    let rawA=directory.appendingPathComponent("rawA.mov"),rawB=directory.appendingPathComponent("rawB.mov"),aURL=directory.appendingPathComponent("A.mov"),bURL=directory.appendingPathComponent("B.mov")
    try await writeDriftVideo(rawA,origin:2,slope:0.999,sparse:sparse);try await writeDriftVideo(rawB,origin:0,slope:1,sparse:sparse)
    try await mergeDriftCamera(video:rawA,audio:cameraAudio,to:aURL);try await mergeDriftCamera(video:rawB,audio:masterURL,to:bURL)
    let hashes=try [aURL,bURL,masterURL].map(driftDigest),pipeline=MediaPipeline()
    let a=try await pipeline.probe(aURL).asset,b=try await pipeline.probe(bURL).asset,master=try await pipeline.probe(masterURL).asset
    #expect(a.duration.seconds>=239.9 && b.duration.seconds>=239.9 && master.duration.seconds==240)
    let store=EditorStore();defer{store.cancelSynchronization();store.replace(ProjectDocument())};store.replace(ProjectDocument(sequence:Sequence(settings:ProjectSettings(width:64,height:64),tracks:[Track(name:"A",kind:.video,clips:[Clip(assetID:a.id,duration:.init(value:239,timescale:1))]),Track(name:"B",kind:.video,clips:[Clip(assetID:b.id,duration:.init(value:239,timescale:1))]),Track(name:"Master",kind:.audio,clips:[Clip(assetID:master.id,duration:master.duration)])]),assets:[a,b,master]));store.createMulticam()
    let baseline=store.document
    store.synchronizeCameras()
    let deadline=ContinuousClock.now.advanced(by:.seconds(45))
    while store.synchronizing,ContinuousClock.now<deadline{try await Task.sleep(for:.milliseconds(20))}
    guard !store.synchronizing else{store.cancelSynchronization();throw DriftNativeTestError.timeout}
    let index=try #require(store.syncCandidates.firstIndex{$0.assetID==a.id}),fit=try #require(store.syncCandidates[index].correction)
    #expect(abs(fit.speed-1/0.999)<0.0002)
    driftPhase("Anchored waveform analysis complete")
    // Keep B fixed so its independently authored source markers are the control.
    store.syncCandidates=store.syncCandidates.filter{$0.assetID==a.id}
    let offsetOnly=try store.synchronizedCandidate()
    store.syncCandidates[0].correctDrift=true
    var candidate=try store.synchronizedCandidate();#expect(store.document==baseline)
    let correctedClip=candidate.sequence.tracks[0].clips[0]
    driftPhase("Corrected clip start=\(correctedClip.start), duration=\(correctedClip.duration), speed=\(correctedClip.speed)")
    store.previewSynchronization();#expect(store.document==baseline && store.syncPreviewing)
    store.cancelSynchronization();#expect(store.document==baseline && !store.syncPreviewing)
    let corrected=try await pipeline.prepare(ProjectSnapshot(document:candidate)),original=try await pipeline.prepare(ProjectSnapshot(document:baseline))
    let offsetOnlyPlayback=try await pipeline.prepare(ProjectSnapshot(document:offsetOnly))
    var control=candidate;control.sequence.multicamGroups[0].cuts=[.init(time:.zero,angleID:b.id)]
    let reference=try await pipeline.prepare(ProjectSnapshot(document:control))
    for track in try await corrected.playerItem.asset.loadTracks(withMediaType:.video) {
        for segment in try await track.load(.segments) {
            let map=segment.timeMapping
            driftPhase("Video track \(track.trackID): source \(map.source.start.value)/\(map.source.start.timescale)+\(map.source.duration.value)/\(map.source.duration.timescale), target \(map.target.start.value)/\(map.target.start.timescale)+\(map.target.duration.value)/\(map.target.duration.timescale)")
        }
    }
    driftPhase("Playback plans prepared")
    func frame(_ playback:PreparedPlayback,_ seconds:Double)async throws->[UInt8] {
        let generator=AVAssetImageGenerator(asset:playback.playerItem.asset);generator.videoComposition=playback.playerItem.videoComposition;generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
        let image=try await generator.image(at:CMTime(seconds:seconds,preferredTimescale:600000)).image;var pixel=[UInt8](repeating:0,count:4)
        pixel.withUnsafeMutableBytes{let context=CGContext(data:$0.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;context.draw(image,in:CGRect(x:0,y:0,width:1,height:1))};return pixel
    }
    for time in [100-3.0/30,100+2.0/30,200-3.0/30,200+2.0/30] {
        let output=try await frame(corrected,time),expected=try await frame(reference,time)
        for channel in 0..<3{#expect(abs(Int(output[channel])-Int(expected[channel]))<15)}
    }
    let naiveLate=try await frame(offsetOnlyPlayback,200+2.0/30),correctLate=try await frame(corrected,200+2.0/30)
    #expect(abs(Int(naiveLate[1])-Int(correctLate[1]))>150)
    driftPhase("Early/late frame controls compared")
    let before=try await driftSamples(original.playerItem.asset,mix:original.playerItem.audioMix),after=try await driftSamples(corrected.playerItem.asset,mix:corrected.playerItem.audioMix)
    #expect(before.count==192000 && after.count==before.count)
    let maximumDifference=zip(before,after).map{abs($0-$1)}.max() ?? 0
    #expect(maximumDifference<0.000001)
    print("[LifeEditor drift] speed=\(fit.speed) confidence=\(fit.confidence) uncertainty=\(fit.uncertaintySeconds)s master sample max difference=\(maximumDifference)")
    driftPhase("Master samples compared")
    let package=directory.appendingPathComponent("Drift.lifeedit");try ProjectPackage.write(candidate,to:package);let reopened=try ProjectPackage.read(from:package);#expect(reopened==candidate)
    let output=directory.appendingPathComponent("drift.mov"),options=ExportOptions(format:.proRes,rangeStart:.init(value:199,timescale:1),rangeDuration:.init(value:2,timescale:1))
    driftPhase("Video range export started")
    let export=Task{try await pipeline.export(ProjectSnapshot(document:reopened),to:output,options:options)}
    let watchdog=Task{try await Task.sleep(for:.seconds(20));driftPhase("Export timeout: cancelling reader");export.cancel()}
    do{try await export.value;watchdog.cancel()}catch{watchdog.cancel();driftPhase("Export unwound: \(error)");throw error}
    driftPhase("Video range export complete")
    let exported=AVAssetImageGenerator(asset:AVURLAsset(url:output)),exportedFrame=try await exported.image(at:CMTime(value:32,timescale:30)).image
    var pixel=[UInt8](repeating:0,count:4);pixel.withUnsafeMutableBytes{let context=CGContext(data:$0.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;context.draw(exportedFrame,in:CGRect(x:0,y:0,width:1,height:1))}
    let expected=try await frame(corrected,200+2.0/30);for channel in 0..<3{#expect(abs(Int(pixel[channel])-Int(expected[channel]))<20)}
    let wav=directory.appendingPathComponent("master-output.wav");try await pipeline.export(ProjectSnapshot(document:reopened),to:wav,options:.init(format:.wav,rangeStart:.init(value:199,timescale:1),rangeDuration:.init(value:2,timescale:1)))
    driftPhase("Audio range export complete")
    let exportedAudio=try await driftSamples(AVURLAsset(url:wav),start:0)
    #expect(exportedAudio.count==after.count)
    let quantizationError=zip(after,exportedAudio).map{abs($0-$1)}.max() ?? 0
    #expect(quantizationError<0.00004)
    for speed in [1.0001,1.000237] {
        var fragments=baseline
        let sourceClip=baseline.sequence.tracks[0].clips[0]
        fragments.sequence.tracks[0].clips=[(0,100),(100,100),(220,19)].map{source,duration in
            Clip(assetID:a.id,start:.init(value:Int64(source),timescale:1),duration:.init(value:Int64(duration),timescale:1),sourceStart:.init(value:Int64(source),timescale:1),preservesPitch:sourceClip.preservesPitch)
        }
        func anchor(_ source:Double)->DriftAnchor{.init(sourceSeconds:source,referenceSeconds:0.1234567+source/speed,confidence:0.9,uncertaintySeconds:0.023)}
        let primeFit=try AffineDriftCorrection.fit(early:anchor(20),middle:anchor(120),late:anchor(220))
        let prime=try MulticamDriftCorrection.applying(primeFit,to:a.id,referenceID:master.id,in:fragments).document
        #expect(prime.sequence.tracks[0].clips[0].end==prime.sequence.tracks[0].clips[1].start)
        let primePrepared=try await pipeline.prepare(ProjectSnapshot(document:prime))
        let seam=try await frame(primePrepared,100.1),gap=try await frame(primePrepared,210)
        #expect(seam[2]>200 && seam[0]<20)
        #expect(gap[0]<5 && gap[1]<5 && gap[2]<5)
        let masterExpected=try await driftSamples(original.playerItem.asset,mix:original.playerItem.audioMix,start:99)
        let masterActual=try await driftSamples(primePrepared.playerItem.asset,mix:primePrepared.playerItem.audioMix,start:99)
        #expect(masterActual.count==192000 && masterExpected.count==masterActual.count)
        let error=zip(masterActual,masterExpected).map{abs($0-$1)}.max() ?? 0
        #expect(error<0.000001)
        let primeOutput=directory.appendingPathComponent("prime-\(Int(speed*1_000_000)).mov")
        let export=Task{try await pipeline.export(ProjectSnapshot(document:prime),to:primeOutput,options:.init(format:.proRes,rangeStart:.init(value:99,timescale:1),rangeDuration:.init(value:2,timescale:1)))}
        let timeout=Task{try await Task.sleep(for:.seconds(20));export.cancel()}
        do{try await export.value;timeout.cancel()}catch{timeout.cancel();throw error}
        let generator=AVAssetImageGenerator(asset:AVURLAsset(url:primeOutput))
        let result=try await generator.image(at:CMTime(value:33,timescale:30)).image
        var actual=[UInt8](repeating:0,count:4);actual.withUnsafeMutableBytes{let context=CGContext(data:$0.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;context.draw(result,in:CGRect(x:0,y:0,width:1,height:1))}
        for channel in 0..<3{#expect(abs(Int(actual[channel])-Int(seam[channel]))<20)}
    }
    #expect(try [aURL,bURL,masterURL].map(driftDigest)==hashes)
}

private enum DriftNativeTestError:Error{case timeout}
