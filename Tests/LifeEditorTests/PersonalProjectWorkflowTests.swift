import Testing
import Foundation
import AppKit
@preconcurrency import AVFoundation
import LifeCore
import LifeMedia
@testable import LifeEditor

/// Connected, deterministic smoke project; not a substitute for human usability.
@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"]=="1"))
func personalProjectTrimTitleFadeCollectReopenAndExport()async throws {
    _ = NSApplication.shared
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("life-personal-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:root)}
    let repository=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let photo=root.appendingPathComponent("photo.png"),music=root.appendingPathComponent("music.wav")
    try FileManager.default.copyItem(at:repository.appendingPathComponent("docs/gallery/source/rehearsal.png"),to:photo)
    let format=try #require(AVAudioFormat(standardFormatWithSampleRate:48000,channels:2))
    let buffer=try #require(AVAudioPCMBuffer(pcmFormat:format,frameCapacity:192000));buffer.frameLength=192000
    for sample in 0..<192000 {
        let value=Float(sin(Double(sample)*2 * .pi*440/48000))*0.2
        buffer.floatChannelData![0][sample]=value;buffer.floatChannelData![1][sample]=value
    }
    do{let file=try AVAudioFile(forWriting:music,settings:format.settings.merging([AVLinearPCMIsNonInterleaved:false]){_,new in new});try file.write(from:buffer)}
    let pipeline=MediaPipeline(),imageAsset=try await pipeline.probe(photo).asset,audioAsset=try await pipeline.probe(music).asset
    let four=RationalTime(value:4,timescale:1),one=RationalTime(value:1,timescale:1),three=RationalTime(value:3,timescale:1)
    let picture=Clip(name:"Rehearsal",assetID:imageAsset.id,duration:four),audio=Clip(name:"Music",assetID:audioAsset.id,duration:four)
    let initial=ProjectDocument(name:"Class performance",sequence:.init(settings:.init(width:320,height:180),tracks:[.init(name:"Picture",kind:.image,clips:[picture]),.init(name:"Music",kind:.audio,clips:[audio])]),assets:[imageAsset,audioAsset])
    let store=EditorStore();store.replace(initial)
    store.apply(.trim(clipID:picture.id,start:one,end:three))
    let trimmed=store.document;store.undo();#expect(store.document==initial);store.redo();#expect(store.document==trimmed)
    store.apply(.trim(clipID:audio.id,start:one,end:three));store.selection=audio.id
    store.setFade(0.25,incoming:true);store.setFade(0.25,incoming:false)
    store.playheadTime=one;store.addTitle()
    let titleID=try #require(store.selection)
    store.editSelected{$0.title?.text="Class performance"}
    store.apply(.trim(clipID:titleID,start:one,end:three))
    TitleLayoutPresetControls(store:store).apply(.lowerThird)
    store.setFade(0.25,incoming:true);store.setFade(0.25,incoming:false)
    let edited=store.document;try edited.validate();#expect(edited.sequence.duration==three)
    let faded=try #require(edited.sequence.tracks[1].clips.first)
    #expect(abs(faded.volume.value(at:.init(value:1,timescale:100))-0.04)<0.00001)
    #expect(abs(faded.volume.value(at:.init(value:199,timescale:100))-0.04)<0.00001)
    let firstOutput=root.appendingPathComponent("before.mov")
    try await pipeline.export(ProjectSnapshot(document:edited),to:firstOutput,options:.init(format:.proRes))
    let package=root.appendingPathComponent("Portable.lifeedit")
    try ProjectPackage.collect(edited,to:package)
    // Original import copies can disappear after collection without breaking it.
    try FileManager.default.removeItem(at:photo);try FileManager.default.removeItem(at:music)
    let reopened=try ProjectPackage.read(from:package)
    #expect(reopened.sequence==edited.sequence);#expect(ProjectPackage.missingAssets(in:reopened).isEmpty)
    let snapshot=ProjectSnapshot(document:reopened),prepared=try await pipeline.prepare(snapshot)
    let preview=AVAssetImageGenerator(asset:prepared.playerItem.asset);preview.videoComposition=prepared.playerItem.videoComposition
    preview.requestedTimeToleranceBefore = .zero;preview.requestedTimeToleranceAfter = .zero
    let secondOutput=root.appendingPathComponent("after.mov")
    try await pipeline.export(snapshot,to:secondOutput,options:.init(format:.proRes))
    let before=AVAssetImageGenerator(asset:AVURLAsset(url:firstOutput)),after=AVAssetImageGenerator(asset:AVURLAsset(url:secondOutput))
    for generator in [before,after]{generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero}
    func pixels(_ image:CGImage)->[UInt8] {
        var bytes=[UInt8](repeating:0,count:320*180*4)
        bytes.withUnsafeMutableBytes{memory in
            let context=CGContext(data:memory.baseAddress,width:320,height:180,bitsPerComponent:8,bytesPerRow:320*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:320,height:180))
        };return bytes
    }
    for time in [CMTime(value:1,timescale:2),CMTime(value:3,timescale:2),CMTime(value:11,timescale:4)] {
        let a=pixels(try await before.image(at:time).image),b=pixels(try await after.image(at:time).image),p=pixels(try await preview.image(at:time).image)
        let savedError=zip(a,b).reduce(0.0){$0+Double(abs(Int($1.0)-Int($1.1)))}/Double(a.count)
        let previewError=zip(p,b).reduce(0.0){$0+Double(abs(Int($1.0)-Int($1.1)))}/Double(a.count)
        #expect(savedError<1);#expect(previewError<5)
    }
    let gap=pixels(try await after.image(at:CMTime(value:1,timescale:2)).image)
    #expect(stride(from:0,to:gap.count,by:4).allSatisfy{gap[$0]<3 && gap[$0+1]<3 && gap[$0+2]<3})
    var withoutTitle=reopened;withoutTitle.sequence.tracks.removeAll{$0.kind == .title}
    let plain=try await pipeline.prepare(.init(document:withoutTitle)),plainGenerator=AVAssetImageGenerator(asset:plain.playerItem.asset)
    plainGenerator.videoComposition=plain.playerItem.videoComposition
    let base=pixels(try await plainGenerator.image(at:CMTime(value:3,timescale:2)).image)
    let withTitle=pixels(try await preview.image(at:CMTime(value:3,timescale:2)).image)
    let changedPixels=stride(from:0,to:base.count,by:4).filter{abs(Int(base[$0])-Int(withTitle[$0]))>10}.count
    #expect(changedPixels>50)
    let photoPixels=stride(from:0,to:base.count,by:4).filter{base[$0]>30 || base[$0+1]>30 || base[$0+2]>30}.count
    #expect(photoPixels>320*180/4)
    let live=PlaybackMeterSource(item:prepared.playerItem),offline=PlaybackMeterSource(item:AVPlayerItem(url:secondOutput))
    let middle=try await PlaybackAudioMeter.read(live,at:.init(value:2,timescale:1)),fade=try await PlaybackAudioMeter.read(live,at:.init(value:101,timescale:100))
    let decoded=try await PlaybackAudioMeter.read(offline,at:.init(value:2,timescale:1))
    let decodedFade=try await PlaybackAudioMeter.read(offline,at:.init(value:101,timescale:100))
    let tail=try await PlaybackAudioMeter.read(offline,at:.init(value:299,timescale:100))
    #expect(abs(fade.frame.leftDBFS-decodedFade.frame.leftDBFS)<0.5)
    #expect(decoded.frame.leftDBFS>decodedFade.frame.leftDBFS+8)
    #expect(decoded.frame.leftDBFS>tail.frame.leftDBFS+8)
    #expect(middle.frame.leftDBFS>fade.frame.leftDBFS+8)
    #expect(abs(middle.frame.leftDBFS-decoded.frame.leftDBFS)<0.5)
}
