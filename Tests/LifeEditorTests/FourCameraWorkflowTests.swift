import Testing
import AppKit
@preconcurrency import AVFoundation
import CoreImage
import LifeCore
import LifeMedia
@testable import LifeEditor

private func workflowPhase(_ message:String){try? FileHandle.standardError.write(contentsOf:Data(("[Four camera phase] "+message+"\n").utf8))}
private func workflowAmplitude(_ t:Double)->Double {
    // Dense, nonrepeating transients avoid the ambiguous one-pulse matches
    // possible in the two-second minimum overlap of a short recording.
    let bin=Int(t*12),phase=t*12-Double(bin)
    var h=UInt64(max(0,bin)) &+ 0x9e3779b97f4a7c15
    h=(h ^ (h >> 30)) &* 0xbf58476d1ce4e5b9;h=(h ^ (h >> 27)) &* 0x94d049bb133111eb;h ^= h >> 31
    let height=h%3==0 ? 0.15+Double((h >> 24)%700)/1000:0.005
    return 0.005+height*exp(-pow((phase-0.4)/0.16,2))
}
private func workflowTone(_ url:URL,offset:Double,frequency:Double)throws {
    let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!,file=try AVAudioFile(forWriting:url,settings:format.settings)
    let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:48000)!;buffer.frameLength=48000
    for second in 0..<20 {
        for i in 0..<48000 {let t=Double(second)+Double(i)/48000+offset;buffer.floatChannelData![0][i]=Float(workflowAmplitude(t)*sin(2 * .pi*frequency*t))}
        try file.write(from:buffer)
    }
}
private func workflowCamera(_ url:URL,audio:URL,color:CIColor)async throws {
    let raw=url.deletingPathExtension().appendingPathExtension("video.mov"),writer=try AVAssetWriter(outputURL:raw,fileType:.mov)
    let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:64,AVVideoHeightKey:64])
    let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:64,kCVPixelBufferHeightKey as String:64]);writer.add(input)
    try #require(writer.startWriting());writer.startSession(atSourceTime:.zero)
    let context=CIContext(),image=CIImage(color:color).cropped(to:CGRect(x:0,y:0,width:64,height:64))
    for frame in 0..<600 {
        while !input.isReadyForMoreMediaData{try await Task.sleep(for:.milliseconds(1))}
        var pixel:CVPixelBuffer?;try #require(CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&pixel)==kCVReturnSuccess)
        context.render(image,to:pixel!);try #require(adaptor.append(pixel!,withPresentationTime:CMTime(value:Int64(frame),timescale:30)))
    }
    writer.endSession(atSourceTime:CMTime(value:20,timescale:1));input.markAsFinished();await writer.finishWriting();try #require(writer.status == .completed)
    let video=AVURLAsset(url:raw),sound=AVURLAsset(url:audio),composition=AVMutableComposition(),range=CMTimeRange(start:.zero,duration:CMTime(value:20,timescale:1))
    let v=try #require(try await video.loadTracks(withMediaType:.video).first),a=try #require(try await sound.loadTracks(withMediaType:.audio).first)
    try composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid)!.insertTimeRange(range,of:v,at:.zero)
    try composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid)!.insertTimeRange(range,of:a,at:.zero)
    let export=try #require(AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetPassthrough))
    // Use the callback bridge also exercised by the drift fixture; the SDK's
    // async export bridge crashes on this CLT/runtime combination.
    export.outputURL=url;export.outputFileType = .mov
    await withCheckedContinuation{(continuation:CheckedContinuation<Void,Never>) in export.exportAsynchronously{continuation.resume()}}
    try #require(export.status == .completed)
}
private func workflowSamples(_ asset:AVAsset,mix:AVAudioMix?=nil)async throws->[Float] {
    let reader=try AVAssetReader(asset:asset),tracks=try await asset.loadTracks(withMediaType:.audio)
    let output=AVAssetReaderAudioMixOutput(audioTracks:tracks,audioSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:48000,AVNumberOfChannelsKey:2,AVLinearPCMBitDepthKey:32,AVLinearPCMIsFloatKey:true,AVLinearPCMIsNonInterleaved:false]);output.audioMix=mix
    reader.add(output);reader.timeRange=CMTimeRange(start:.zero,duration:CMTime(value:4,timescale:1));try #require(reader.startReading());var result:[Float]=[]
    while let sample=output.copyNextSampleBuffer(),let block=CMSampleBufferGetDataBuffer(sample){let n=CMSampleBufferGetNumSamples(sample)*2;var chunk=[Float](repeating:0,count:n);try #require(chunk.withUnsafeMutableBytes{CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:n*4,destination:$0.baseAddress!)}==kCMBlockBufferNoErr);result+=chunk}
    try #require(reader.status == .completed);return result
}
private func workflowPixel(_ generator:AVAssetImageGenerator,_ time:RationalTime)async throws->[UInt8] {
    generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
    let image=try await generator.image(at:CMTime(value:time.value,timescale:CMTimeScale(time.timescale))).image
    var pixel=[UInt8](repeating:0,count:4);pixel.withUnsafeMutableBytes{let context=CGContext(data:$0.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;context.draw(image,in:CGRect(x:0,y:0,width:1,height:1))};return pixel
}
@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"]=="1"))
func fourCameraWaveformSwitchRefineReopenExportKeepsSeparateMaster()async throws {
    _ = NSApplication.shared
    workflowPhase("Start fixture")
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("life-four-camera-"+UUID().uuidString);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:directory)}
    let masterURL=directory.appendingPathComponent("Master.wav");try await Task.detached{try workflowTone(masterURL,offset:0,frequency:660)}.value
    let colors=[CIColor(red:1,green:0,blue:0),CIColor(red:0,green:0,blue:1),CIColor(red:0,green:1,blue:0),CIColor(red:1,green:1,blue:0)],offsets=[0.0,0.2,0.4,0.6]
    let pipeline=MediaPipeline();var assets:[MediaAsset]=[],tracks:[Track]=[]
    for index in 0..<4 {
        let wav=directory.appendingPathComponent("Camera\(index).wav"),mov=directory.appendingPathComponent("Camera\(index).mov"),offset=offsets[index],frequency=440+Double(index)*110
        try await Task.detached{try workflowTone(wav,offset:offset,frequency:frequency)}.value
        try await workflowCamera(mov,audio:wav,color:colors[index]);let asset=try await pipeline.probe(mov).asset;assets.append(asset)
        tracks.append(Track(name:"Camera \(index+1)",kind:.video,clips:[Clip(assetID:asset.id,duration:.init(value:18,timescale:1))]))
    }
    let master=try await pipeline.probe(masterURL).asset;assets.append(master);tracks.append(Track(name:"Master",kind:.audio,clips:[Clip(assetID:master.id,duration:master.duration)]))
    let store=EditorStore();store.replace(ProjectDocument(sequence:Sequence(settings:ProjectSettings(width:64,height:64),tracks:tracks),assets:assets));store.createMulticam()
    defer{store.stopPlayback();store.cancelSynchronization();store.replace(ProjectDocument())}
    store.synchronizeCameras();let deadline=ContinuousClock.now.advanced(by:.seconds(30))
    while store.synchronizing,ContinuousClock.now<deadline{try await Task.sleep(for:.milliseconds(10))}
    try #require(!store.synchronizing && store.syncCandidates.count==4)
    // Short recordings can have ambiguous local matches. Keep their confidence
    // visible and explicitly review the known offset instead of treating them
    // as confident automatic matches.
    #expect(store.syncCandidates.filter{$0.confidence>=0.6}.count>=3)
    #expect(store.syncCandidates.contains{$0.confidence<0.6})
    for (index,asset) in assets.prefix(4).enumerated(){
        let candidate=try #require(store.syncCandidates.firstIndex{$0.assetID==asset.id}),result=store.syncCandidates[candidate]
        print("[Four camera] index=\(index) offset=\(result.offset) confidence=\(result.confidence)")
        #expect(abs(result.offset-offsets[index])<0.05)
        if result.confidence<0.6 {store.syncCandidates[candidate].offset=offsets[index];#expect(store.syncCandidates[candidate].confidence==result.confidence)}
    }
    workflowPhase("Sync preview")
    let beforeSync=store.document;store.previewSynchronization();#expect(store.document==beforeSync)
    store.applySynchronization();try #require(store.error==nil)
    workflowPhase("Sync applied")
    let synchronized=store.document,masterTrack=try #require(synchronized.sequence.tracks.first{$0.kind == .audio}),before=try await pipeline.prepare(ProjectSnapshot(document:synchronized))
    let baselineAudio=try await workflowSamples(before.playerItem.asset,mix:before.playerItem.audioMix)
    workflowPhase("Record pass")
    let canvas=TimelineCanvas(store:store);store.panel = .multicam;store.switchMode = .video;store.switchArmed=true;store.seek(0);store.togglePlayback()
    for index in 1..<4 {
        store.playheadTime = .init(value:Int64(index),timescale:1)
        let key=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:String(index+1),charactersIgnoringModifiers:String(index+1),isARepeat:false,keyCode:0))
        canvas.keyDown(with:key)
    }
    store.stopPlayback();store.switchArmed=false
    let recorded=store.document;#expect(recorded.sequence.multicamGroups[0].cuts.count==4)
    store.undo();#expect(store.document==synchronized);store.redo();#expect(store.document==recorded)
    let cut=try #require(store.multicamGroup?.cuts.first{$0.angleID==assets[1].id})
    workflowPhase("Pointer refinement")
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:500),styleMask:[.titled],backing:.buffered,defer:false)
    window.contentView=canvas;canvas.frame=NSRect(x:0,y:0,width:900,height:500);defer{window.orderOut(nil)}
    store.snapping=false
    func pointer(_ type:NSEvent.EventType,_ p:NSPoint)->NSEvent{NSEvent.mouseEvent(with:type,location:canvas.convert(p,to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!}
    let origin=NSPoint(x:canvas.x(cut.time.seconds),y:46),target=NSPoint(x:canvas.x(1.2),y:46)
    canvas.mouseDown(with:pointer(.leftMouseDown,origin));canvas.mouseDragged(with:pointer(.leftMouseDragged,target))
    #expect(store.document==recorded);try #require(canvas.cutDrag?.proposal != nil)
    canvas.mouseUp(with:pointer(.leftMouseUp,target));let refined=store.document
    #expect(refined.sequence.multicamGroups[0].cuts.first{$0.id==cut.id}?.time == .init(value:6,timescale:5))
    #expect(refined.sequence.tracks.first{$0.kind == .audio}==masterTrack)
    #expect(refined.sequence.multicamGroups[0].audioCuts==synchronized.sequence.multicamGroups[0].audioCuts)
    store.undo();#expect(store.document==recorded);store.redo();#expect(store.document==refined)
    workflowPhase("Save and compare preview")
    let package=directory.appendingPathComponent("Performance.lifeedit");try ProjectPackage.write(refined,to:package);let reopened=try ProjectPackage.read(from:package);#expect(reopened==refined)
    let preview=try await pipeline.prepare(ProjectSnapshot(document:reopened)),generator=AVAssetImageGenerator(asset:preview.playerItem.asset);generator.videoComposition=preview.playerItem.videoComposition
    let afterAudio=try await workflowSamples(preview.playerItem.asset,mix:preview.playerItem.audioMix)
    #expect(baselineAudio.count==384000 && afterAudio.count==baselineAudio.count)
    #expect(zip(baselineAudio,afterAudio).allSatisfy{abs($0-$1)<0.000001})
    workflowPhase("ProRes export")
    let destination=directory.appendingPathComponent("Performance.mov");try await pipeline.export(ProjectSnapshot(document:reopened),to:destination,options:.init(format:.proRes,rangeStart:.zero,rangeDuration:.init(value:4,timescale:1)))
    let exported=AVURLAsset(url:destination),decoded=AVAssetImageGenerator(asset:exported)
    for (time,index) in [(RationalTime(value:11,timescale:10),0),(.init(value:13,timescale:10),1),(.init(value:5,timescale:2),2),(.init(value:7,timescale:2),3)] {
        let expected=try await workflowPixel(generator,time),actual=try await workflowPixel(decoded,time)
        // Assert angle identity independently of decoder color-matrix rounding.
        switch index {
        case 0:#expect(Int(expected[0])>Int(expected[1])+100 && Int(expected[0])>Int(expected[2])+100)
        case 1:#expect(Int(expected[2])>Int(expected[0])+100 && Int(expected[2])>Int(expected[1])+100)
        case 2:#expect(Int(expected[1])>Int(expected[0])+100 && Int(expected[1])>Int(expected[2])+100)
        default:#expect(Int(expected[0])>Int(expected[2])+100 && Int(expected[1])>Int(expected[2])+100)
        }
        for channel in 0..<3{#expect(abs(Int(actual[channel])-Int(expected[channel]))<20)}
    }
    workflowPhase("WAV export")
    let wav=directory.appendingPathComponent("Performance.wav");try await pipeline.export(ProjectSnapshot(document:reopened),to:wav,options:.init(format:.wav,rangeStart:.zero,rangeDuration:.init(value:4,timescale:1)))
    workflowPhase("Compare PCM")
    let pcm=try await workflowSamples(AVURLAsset(url:wav));#expect(pcm.count==afterAudio.count);#expect(zip(pcm,afterAudio).allSatisfy{abs($0-$1)<0.00004})
}
