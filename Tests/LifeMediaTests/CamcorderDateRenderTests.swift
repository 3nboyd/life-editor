import Foundation
import Testing
@preconcurrency import AVFoundation
import CoreImage
import LifeCore
@testable import LifeMedia

@Test func camcorderDateMetadataRejectsNetworkWithoutReading()async throws {
    let asset=MediaAsset(url:URL(string:"https://example.invalid/video.mov")!,kind:.video,duration:.init(value:1,timescale:1))
    do{_ = try await CamcorderRecordingDate.candidate(for:asset);Issue.record("Remote metadata must be rejected")}
    catch HelperError.localFilesOnly {} catch {throw error}
}

@Test func camcorderDateMetadataCandidatesRejectAmbiguity() {
    #expect(CamcorderRecordingDate.candidate(from:["2020-01-01T12:00:00"])==nil)
    #expect(CamcorderRecordingDate.candidate(from:["2020-01-01T12:00:00Z","2021-01-01T12:00:00Z"])==nil)
    #expect(CamcorderRecordingDate.candidate(from:["2020-01-01T12:00:00Z","2020-01-01T12:00:00Z"]) != nil)
}

@Test func camcorderDatePixelsAreDeterministicAndCornersMove()throws {
    let canvas=CGRect(x:0,y:0,width:320,height:180),context=CIContext()
    let source=CIImage(color:CIColor(red:0.15,green:0.1,blue:0.2)).cropped(to:canvas)
    var overlay=try #require(CamcorderDateOverlay.parse("1999-12-31T23:59:59Z"))
    func bytes(_ image:CIImage)->[UInt8]{var result=[UInt8](repeating:0,count:320*180*4);context.render(image,toBitmap:&result,rowBytes:320*4,bounds:canvas,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB));return result}
    let first=bytes(CamcorderDateRenderer.apply(overlay,to:source,sourceTime:.zero))
    #expect(first==bytes(CamcorderDateRenderer.apply(overlay,to:source,sourceTime:.zero)))
    #expect(first != bytes(CamcorderDateRenderer.apply(overlay,to:source,sourceTime:.init(value:1,timescale:1))))
    overlay.corner = .topLeft
    let moved=bytes(CamcorderDateRenderer.apply(overlay,to:source,sourceTime:.zero))
    #expect(first != moved)
    overlay.enabled=false
    #expect(bytes(CamcorderDateRenderer.apply(overlay,to:source,sourceTime:.zero))==bytes(source))
}

@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"]=="1"))
func camcorderDateNativeSourceClockRetimingFreezeMetadataAndExport()async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("life-date-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:directory)}
    let original=directory.appendingPathComponent("original.mov"),prepared=directory.appendingPathComponent("prepared.mov")
    let writer=try AVAssetWriter(outputURL:original,fileType:.mov)
    let metadata=AVMutableMetadataItem();metadata.identifier = .quickTimeMetadataCreationDate;metadata.value="1999-12-31T23:59:59-05:00" as NSString
    writer.metadata=[metadata]
    let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:320,AVVideoHeightKey:180])
    let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:320,kCVPixelBufferHeightKey as String:180])
    writer.add(input);try #require(writer.startWriting());writer.startSession(atSourceTime:.zero)
    let context=CIContext(),canvas=CGRect(x:0,y:0,width:320,height:180)
    for frame in 0..<90 {
        while !input.isReadyForMoreMediaData{try await Task.sleep(for:.milliseconds(1))}
        var buffer:CVPixelBuffer?;try #require(CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&buffer)==kCVReturnSuccess)
        context.render(CIImage(color:CIColor(red:0.15,green:0.1,blue:0.2)).cropped(to:canvas),to:buffer!)
        try #require(adaptor.append(buffer!,withPresentationTime:CMTime(value:Int64(frame),timescale:30)))
    }
    input.markAsFinished();await writer.finishWriting();try #require(writer.status == .completed)
    try FileManager.default.copyItem(at:original,to:prepared)
    let pipeline=MediaPipeline();var asset=try await pipeline.probe(original).asset;asset.preparedURL=directory.appendingPathComponent("missing-conversion.mov")
    let candidate=try #require(try await CamcorderRecordingDate.candidate(for:asset))
    asset.preparedURL=prepared
    #expect(candidate.origin == .recorded && candidate.utcOffsetSeconds == -18000)
    #expect(candidate.text(at:.init(value:1,timescale:1))=="2000-01-01 00:00:00")
    var effect=NativeEffectRegistry.make("life.filter.VHS");effect.parameters["grain"]=0;effect.camcorderDate=candidate
    let clip=Clip(assetID:asset.id,duration:.init(value:1,timescale:1),sourceStart:.init(value:1,timescale:2),speed:2,effects:[effect])
    let settings=ProjectSettings(width:320,height:180)
    let editor=ProjectEditor(document:ProjectDocument(sequence:Sequence(settings:settings,tracks:[Track(name:"Video",kind:.video,clips:[clip])]),assets:[asset]))
    let originalDocument=editor.document
    try editor.perform(.split(clipID:clip.id,at:.init(value:1,timescale:2)));editor.undo()
    #expect(editor.document==originalDocument)
    let package=directory.appendingPathComponent("Date.lifeedit");try ProjectPackage.write(editor.document,to:package)
    let document=try ProjectPackage.read(from:package);#expect(document==originalDocument)
    let snapshot=ProjectSnapshot(document:document),playback=try await pipeline.prepare(snapshot)
    let generator=AVAssetImageGenerator(asset:playback.playerItem.asset);generator.videoComposition=playback.playerItem.videoComposition;generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
    let time=CMTime(value:15,timescale:30),preview=try await generator.image(at:time).image
    let destination=directory.appendingPathComponent("date.mp4");try await pipeline.export(snapshot,to:destination)
    let exportedGenerator=AVAssetImageGenerator(asset:AVURLAsset(url:destination));exportedGenerator.requestedTimeToleranceBefore = .zero;exportedGenerator.requestedTimeToleranceAfter = .zero
    let exported=try await exportedGenerator.image(at:time).image
    func pixels(_ image:CGImage)->[UInt8]{var bytes=[UInt8](repeating:0,count:320*180*4);context.render(CIImage(cgImage:image),toBitmap:&bytes,rowBytes:320*4,bounds:canvas,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB));return bytes}
    let a=pixels(preview),b=pixels(exported)
    let whiteIndices=stride(from:0,to:a.count,by:4).filter{a[$0]>190 && a[$0+1]>190 && a[$0+2]>190}
    #expect(whiteIndices.count>20)
    let raw=try await pipeline.thumbnail(asset:asset,at:clip.sourceTime(at:.init(value:1,timescale:2)))
    let expected=EffectRenderer.apply([effect],to:CIImage(cgImage:raw),time:.init(value:1,timescale:2),sourceTime:clip.sourceTime(at:.init(value:1,timescale:2)))
    let wrong=EffectRenderer.apply([effect],to:CIImage(cgImage:raw),time:.init(value:1,timescale:2),sourceTime:.init(value:1,timescale:2))
    let expectedCG=try #require(context.createCGImage(expected,from:canvas)),wrongCG=try #require(context.createCGImage(wrong,from:canvas))
    let expectedPixels=pixels(expectedCG),wrongPixels=pixels(wrongCG)
    let expectedError=zip(a,expectedPixels).reduce(0){$0+abs(Int($1.0)-Int($1.1))}
    let wrongError=zip(a,wrongPixels).reduce(0){$0+abs(Int($1.0)-Int($1.1))}
    #expect(expectedError<wrongError)
    let repeated=try await generator.image(at:time).image
    #expect(pixels(repeated)==a)
    let error=whiteIndices.reduce(0){$0+abs(Int(a[$1])-Int(b[$1]))}/max(1,whiteIndices.count)
    #expect(error<30)
    let thumbnail=try await pipeline.thumbnail(asset:asset,at:clip.sourceTime(at:.init(value:1,timescale:2)),effects:[effect])
    #expect(pixels(thumbnail).contains{$0>220})
    // Freeze source clocks hold even though the timeline/effect animation clock moves.
    var frozen=clip;frozen.sourceStart = .init(value:3,timescale:2);frozen.speed=1;frozen.audioEnabled=false
    frozen.duration = .init(value:2,timescale:1)
    frozen.freezeFrame=FreezeFrameContent(sourceTime:frozen.sourceStart)
    #expect(candidate.text(at:frozen.sourceTime(at:.zero))==candidate.text(at:frozen.sourceTime(at:.init(value:10,timescale:1))))
    let frozenDocument=ProjectDocument(sequence:Sequence(settings:settings,tracks:[Track(name:"Freeze",kind:.video,clips:[frozen])]),assets:[asset])
    let frozenPlayback=try await pipeline.prepare(ProjectSnapshot(document:frozenDocument))
    let frozenGenerator=AVAssetImageGenerator(asset:frozenPlayback.playerItem.asset);frozenGenerator.videoComposition=frozenPlayback.playerItem.videoComposition;frozenGenerator.requestedTimeToleranceBefore = .zero;frozenGenerator.requestedTimeToleranceAfter = .zero
    let frozenTime=CMTime(value:45,timescale:30)
    let frozenPreview=try await frozenGenerator.image(at:frozenTime).image
    #expect(pixels(frozenPreview).contains{$0>220})
    let frozenStart=try await frozenGenerator.image(at:.zero).image
    func whiteMask(_ image:CGImage)->[Bool]{let data=pixels(image);return stride(from:0,to:data.count,by:4).map{data[$0]>190 && data[$0+1]>190 && data[$0+2]>190}}
    // VHS changes the background under antialiased edges; the timestamp
    // glyphs hold, allowing at most two threshold-edge pixels to differ.
    let frozenDifferences=zip(whiteMask(frozenPreview),whiteMask(frozenStart)).filter{$0 != $1}.count
    #expect(frozenDifferences<=2)
    let frozenExport=directory.appendingPathComponent("frozen-date.mp4")
    try await pipeline.export(ProjectSnapshot(document:frozenDocument),to:frozenExport)
    let frozenExportGenerator=AVAssetImageGenerator(asset:AVURLAsset(url:frozenExport))
    let frozenOutput=try await frozenExportGenerator.image(at:frozenTime).image
    let maskA=whiteMask(frozenPreview),maskB=whiteMask(frozenOutput)
    let differing=zip(maskA,maskB).filter{$0 != $1}.count
    #expect(differing<30)
}
