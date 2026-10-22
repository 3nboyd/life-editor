import Testing
@preconcurrency import AVFoundation
import CoreImage
import LifeCore
@testable import LifeMedia

@MainActor @Test func freezeFrameNativeLastTimestampPreviewExportAndSilentExtension()async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("life-freeze-"+UUID().uuidString);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:directory)}
    var source=directory.appendingPathComponent("source.mov");let writer=try AVAssetWriter(outputURL:source,fileType:.mov)
    let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:64,AVVideoHeightKey:64])
    let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:64,kCVPixelBufferHeightKey as String:64])
    writer.add(input);try #require(writer.startWriting());writer.startSession(atSourceTime:.zero);let context=CIContext()
    // Deliberately irregular timestamps prove this does not guess a nominal/project frame rate.
    for (index,tick) in [0,10,29].enumerated(){
        while !input.isReadyForMoreMediaData{try await Task.sleep(for:.milliseconds(1))}
        var buffer:CVPixelBuffer?;try #require(CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&buffer)==kCVReturnSuccess)
        context.render(CIImage(color:index==2 ? CIColor(red:0,green:0,blue:1):CIColor(red:1,green:0,blue:0)).cropped(to:CGRect(x:0,y:0,width:64,height:64)),to:buffer!)
        try #require(adaptor.append(buffer!,withPresentationTime:CMTime(value:Int64(tick),timescale:30)))
    }
    input.markAsFinished();await writer.finishWriting();try #require(writer.status == .completed)
    let videoAsset=AVURLAsset(url:source),sourceDuration=try await videoAsset.load(.duration)
    let toneURL=directory.appendingPathComponent("tone.wav"),format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
    let frameCount=AVAudioFrameCount((sourceDuration.seconds*48000).rounded()),audio=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:frameCount)!
    audio.frameLength=frameCount;for index in 0..<Int(frameCount){audio.floatChannelData![0][index]=Float(sin(Double(index)*2 * .pi*440/48000))*0.5};do{let file=try AVAudioFile(forWriting:toneURL,settings:format.settings);try file.write(from:audio)}
    let merged=AVMutableComposition(),videoTrack=try #require(try await videoAsset.loadTracks(withMediaType:.video).first),toneAsset=AVURLAsset(url:toneURL),toneTrack=try #require(try await toneAsset.loadTracks(withMediaType:.audio).first)
    try merged.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid)!.insertTimeRange(CMTimeRange(start:.zero,duration:sourceDuration),of:videoTrack,at:.zero)
    try merged.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid)!.insertTimeRange(CMTimeRange(start:.zero,duration:sourceDuration),of:toneTrack,at:.zero)
    source=directory.appendingPathComponent("source-with-audio.mov")
    let merger=try #require(AVAssetExportSession(asset:merged,presetName:AVAssetExportPresetPassthrough));merger.outputURL=source;merger.outputFileType = .mov
    // The current CLT async importer crashes in this API's synthesized completion bridge.
    await withCheckedContinuation{(continuation:CheckedContinuation<Void,Never>) in merger.exportAsynchronously{continuation.resume()}}
    try #require(merger.status == .completed,"Merge error: \(String(describing:merger.error))")
    let pipeline=MediaPipeline(),probe=try await pipeline.probe(source),last=try await pipeline.lastVideoFrameTime(asset:probe.asset)
    #expect(probe.hasAudio)
    #expect(last == RationalTime(value:29,timescale:30))
    let clip=Clip(assetID:probe.asset.id,duration:probe.asset.duration),editor=ProjectEditor(document:ProjectDocument(sequence:Sequence(settings:ProjectSettings(width:64,height:64),tracks:[Track(name:"Video",kind:.video,clips:[clip])]),assets:[probe.asset]))
    let originalPrepared=try await pipeline.prepare(editor.snapshot),originalPreview=AVAssetImageGenerator(asset:originalPrepared.playerItem.asset)
    originalPreview.videoComposition=originalPrepared.playerItem.videoComposition;originalPreview.requestedTimeToleranceBefore = .zero;originalPreview.requestedTimeToleranceAfter = .zero
    let expectedFrame=try await originalPreview.image(at:CMTime(value:last.value,timescale:Int32(last.timescale))).image
    try editor.perform(.extendFreezeFrame(clipID:clip.id,duration:.init(value:1,timescale:1),sourceFrameTime:last))
    let package=directory.appendingPathComponent("Frozen.lifeedit");try ProjectPackage.write(editor.document,to:package);let reopened=try ProjectPackage.read(from:package);#expect(reopened==editor.document)
    let snapshot=ProjectSnapshot(document:reopened),prepared=try await pipeline.prepare(snapshot),preview=AVAssetImageGenerator(asset:prepared.playerItem.asset)
    preview.videoComposition=prepared.playerItem.videoComposition;preview.requestedTimeToleranceBefore = .zero;preview.requestedTimeToleranceAfter = .zero
    let sample=CMTimeAdd(CMTime(value:probe.asset.duration.value,timescale:Int32(probe.asset.duration.timescale)),CMTime(value:15,timescale:30))
    let previewFrame=try await preview.image(at:sample).image
    let exported=directory.appendingPathComponent("freeze.mp4");try await pipeline.export(snapshot,to:exported)
    let result=AVURLAsset(url:exported),generator=AVAssetImageGenerator(asset:result),exportFrame=try await generator.image(at:sample).image
    func pixel(_ image:CGImage)->[UInt8]{var bytes=[UInt8](repeating:0,count:4);bytes.withUnsafeMutableBytes{buffer in let cg=CGContext(data:buffer.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;cg.draw(image,in:CGRect(x:0,y:0,width:1,height:1))};return bytes}
    let expected=pixel(expectedFrame),a=pixel(previewFrame),b=pixel(exportFrame)
    #expect(Int(expected[2])-Int(expected[0])>150)
    for channel in 0..<3{#expect(abs(Int(a[channel])-Int(expected[channel]))<20);#expect(abs(Int(b[channel])-Int(expected[channel]))<20)}
    let outputAudio=try #require(try await result.loadTracks(withMediaType:.audio).first)
    let audioReader=try AVAssetReader(asset:result),audioOutput=AVAssetReaderTrackOutput(track:outputAudio,outputSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVLinearPCMIsFloatKey:true,AVLinearPCMBitDepthKey:32,AVLinearPCMIsNonInterleaved:false])
    audioReader.add(audioOutput);try #require(audioReader.startReading())
    var originalPeak:Float=0,freezePeak:Float=0
    while let sample=audioOutput.copyNextSampleBuffer(){
        guard let block=CMSampleBufferGetDataBuffer(sample) else{continue}
        let length=CMBlockBufferGetDataLength(block);var bytes=[UInt8](repeating:0,count:length)
        try #require(CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:length,destination:&bytes)==noErr)
        let peak=bytes.withUnsafeBytes{$0.bindMemory(to:Float.self).reduce(Float(0)){max($0,abs($1))}}
        let time=CMSampleBufferGetPresentationTimeStamp(sample).seconds
        if time<0.5{originalPeak=max(originalPeak,peak)}
        if time>probe.asset.duration.seconds+0.1{freezePeak=max(freezePeak,peak)}
    }
    #expect(audioReader.status == .completed);#expect(originalPeak>0.1);#expect(freezePeak<0.001)
    let frozen=try #require(reopened.sequence.tracks[0].clips.last);#expect(frozen.audioEnabled==false)
    // An already-cancelled caller must not start a tail scan.
    let cancelled=Task{try await pipeline.lastVideoFrameTime(asset:probe.asset)};cancelled.cancel()
    do{_ = try await cancelled.value;Issue.record("Cancelled freeze scan completed")}catch is CancellationError{}catch{Issue.record("Unexpected cancellation: \(error)")}
    let cancelledDecode=Task{try await pipeline.frozenFrameImage(asset:probe.asset,time:last,size:CGSize(width:64,height:64))};cancelledDecode.cancel()
    do{_ = try await cancelledDecode.value;Issue.record("Cancelled freeze decode completed")}catch is CancellationError{}catch{Issue.record("Unexpected decode cancellation: \(error)")}
}
