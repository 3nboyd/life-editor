import Testing
@preconcurrency import AVFoundation
import CoreImage
import LifeCore
@testable import LifeMedia
private func layerTime(_ n:Int64,_ d:Int64=1)->RationalTime{.init(value:n,timescale:d)}
@MainActor private func adjustmentFixture()throws->ProjectDocument{
    let red=Clip(duration:layerTime(3),graphic:.shape(.init(kind:.rectangle,rect:.init(x:0,y:0,width:1,height:1),fill:.init(red:1,green:0,blue:0),strokeWidth:0)))
    let base=ProjectDocument(sequence:Sequence(settings:ProjectSettings(width:64,height:64),tracks:[Track(name:"Below",kind:.shape,clips:[red])]))
    var document=try AdjustmentLayers.adding(at:layerTime(1),duration:layerTime(1),in:base)
    document.sequence.tracks[1].clips[0].effects=[EffectInstance(stableID:"life.filter.grayscale")]
    let blue=Clip(duration:layerTime(3),graphic:.shape(.init(kind:.rectangle,rect:.init(x:0.5,y:0,width:0.5,height:1),fill:.init(red:0,green:0,blue:1),strokeWidth:0)))
    document.sequence.tracks.append(Track(name:"Above",kind:.shape,clips:[blue]));return document
}
private func adjustmentPixel(_ image:CGImage,x:Int=8,y:Int=32)->[UInt8]{
    var bytes=[UInt8](repeating:0,count:4)
    bytes.withUnsafeMutableBytes{buffer in let context=CGContext(data:buffer.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;context.draw(image,in:CGRect(x:-x,y:-y,width:image.width,height:image.height))};return bytes
}
@MainActor private func adjustmentFrame(_ document:ProjectDocument,_ at:RationalTime)async throws->CGImage{
    let prepared=try await MediaPipeline().prepare(.init(document:document)),generator=AVAssetImageGenerator(asset:prepared.playerItem.asset)
    generator.videoComposition=prepared.playerItem.videoComposition;generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
    return try await generator.image(at:CMTime(value:at.value,timescale:Int32(at.timescale))).image
}
@MainActor @Test func adjustmentLayersAffectOnlyBelowWithinTimedBoundsAndPreserveAbove()async throws{
    let document=try adjustmentFixture(),before=adjustmentPixel(try await adjustmentFrame(document,layerTime(1,2))),during=try await adjustmentFrame(document,layerTime(3,2)),after=adjustmentPixel(try await adjustmentFrame(document,layerTime(5,2)))
    let gray=adjustmentPixel(during),above=adjustmentPixel(during,x:56)
    var baseline=document;baseline.sequence.tracks.remove(at:1)
    let sourcePixel=adjustmentPixel(try await adjustmentFrame(baseline,layerTime(3,2)))
    #expect(before==sourcePixel);#expect(after==sourcePixel)
    #expect(Int(sourcePixel[0])-Int(sourcePixel[1])>150)
    #expect(abs(Int(gray[0])-Int(gray[1]))<5 && abs(Int(gray[1])-Int(gray[2]))<5)
    #expect(above[2]>200 && above[0]<30)
    var hidden=document;hidden.sequence.tracks[1].isHidden=true
    #expect(adjustmentPixel(try await adjustmentFrame(hidden,layerTime(3,2)))[0]>200)
    var bypass=document;bypass.sequence.tracks[1].clips[0].effects?[0].isEnabled=false
    #expect(adjustmentPixel(try await adjustmentFrame(bypass,layerTime(3,2)))[0]>200)
    var blend=document;blend.sequence.tracks[1].clips[0].effects?[0].strength=0.5;blend.sequence.tracks[1].clips[0].opacity.baseValue=0.5
    let mixed=adjustmentPixel(try await adjustmentFrame(blend,layerTime(3,2)))
    #expect(mixed[0]>gray[0] && mixed[1]>before[1] && mixed[1]<gray[1])
    var zero=blend;zero.sequence.tracks[1].clips[0].opacity.baseValue=0
    #expect(adjustmentPixel(try await adjustmentFrame(zero,layerTime(3,2)))==before)
}
@MainActor @Test func adjustmentLayersSeededPreviewExportSaveUndoAndMalformedContents()async throws{
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:directory)}
    var document=try adjustmentFixture();document.sequence.tracks[1].clips[0].effects=[EffectInstance(stableID:"life.filter.VHS",parameters:["grain":1],strength:0.7,seed:123)]
    let editor=ProjectEditor(),initial=editor.document;try editor.perform(.replace(document));editor.undo();#expect(editor.document==initial);editor.redo()
    let package=directory.appendingPathComponent("Adjust.lifeedit");try ProjectPackage.write(editor.document,to:package);let reopened=try ProjectPackage.read(from:package);#expect(reopened==document)
    let a=try await adjustmentFrame(reopened,layerTime(3,2)),again=try await adjustmentFrame(reopened,layerTime(3,2));#expect(adjustmentPixel(a)==adjustmentPixel(again))
    let moved=ProjectEditor(document:reopened),adjustmentID=reopened.sequence.tracks[1].clips[0].id
    try moved.perform(.move(clipID:adjustmentID,to:layerTime(1,2)))
    try moved.perform(.trim(clipID:adjustmentID,start:.zero,end:layerTime(3,2)))
    try moved.perform(.split(clipID:adjustmentID,at:layerTime(3,4)))
    let clockFrame=try await adjustmentFrame(moved.document,layerTime(1))
    #expect(adjustmentPixel(clockFrame)==adjustmentPixel(a))
    let url=directory.appendingPathComponent("adjust.mov");try await MediaPipeline().export(.init(document:reopened),to:url,options:.init(format:.proRes))
    let output=AVAssetImageGenerator(asset:AVURLAsset(url:url)),b=try await output.image(at:CMTime(value:3,timescale:2)).image
    for x in [8,16,24,56]{let p=adjustmentPixel(a,x:x),q=adjustmentPixel(b,x:x);for channel in 0..<3{#expect(abs(Int(p[channel])-Int(q[channel]))<20)}}
    var malformed=document;malformed.sequence.tracks[1].clips[0].title=TitleContent(text:"Preserve")
    do{_ = try await MediaPipeline().prepare(.init(document:malformed));Issue.record("Adjustment title silently ignored")}catch AdjustmentLayerError.invalidContents{}catch{Issue.record("Unexpected malformed layer error: \(error)")}
}
