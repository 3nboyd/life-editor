import Foundation
import Testing
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import AVFoundation
import LifeCore
import LifeMedia
@testable import LifeEditor

/// A connected styled-social workflow, independent of optional transcription.
@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"]=="1"))
func styledSocialColorDrawingCaptionsCollectReopenAndExport()async throws {
    _ = NSApplication.shared
    let kept=ProcessInfo.processInfo.environment["LIFE_CREATIVE_ARTIFACTS"].map{URL(fileURLWithPath:$0,isDirectory:true)}
    let width=kept == nil ? 180:720,height=kept == nil ? 320:1280
    let root=kept ?? FileManager.default.temporaryDirectory.appendingPathComponent("life-creative-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer{if kept==nil{try? FileManager.default.removeItem(at:root)}}
    let repository=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let imageURL=root.appendingPathComponent("rehearsal.png")
    try FileManager.default.copyItem(at:repository.appendingPathComponent("docs/gallery/source/rehearsal.png"),to:imageURL)
    let pipeline=MediaPipeline(),probe=try await pipeline.probe(imageURL)
    let visual=try CropGeometry.placing(.init(),source:.init(width:Double(probe.width),height:Double(probe.height)),canvas:.init(width:Double(width),height:Double(height)),mode:.fill)
    let picture=Clip(name:"Rehearsal",assetID:probe.asset.id,duration:.init(value:3,timescale:1),visual:visual)
    let cues=try SRT.parse("1\n00:00:00,250 --> 00:00:01,250\nAt rehearsal\n\n2\n00:00:01,500 --> 00:00:02,750\nOne more take\n")
    let document=ProjectDocument(name:"Creative checkpoint",sequence:.init(settings:.init(width:width,height:height),tracks:[.init(name:"Picture",kind:.image,clips:[picture]),.init(name:"Captions",kind:.caption,clips:cues.map(\.clip))]),assets:[probe.asset])
    let store=EditorStore();store.replace(document);store.selection=picture.id
    let color=AdvancedColorControls(store:store)
    color.setParameter("life.adjust.curves","master2",0.56)
    color.setParameter("life.adjust.levels","gamma",1.12)
    color.setParameter("life.adjust.hsl","yellowSaturation",-0.2)
    store.selection=cues[0].id;store.applyCaptionPreset(.pill)
    store.matchCaptionTrackStyle()
    let styled=store.document;store.undo();store.redo();#expect(store.document==styled)
    store.selection=nil;store.playheadTime = .zero;store.drawingMode=2
    store.drawingColor = .init(red:1,green:0.2,blue:0.6,alpha:0.8);store.drawingWidth=0.025
    store.commitDrawing([.init(x:0.15,y:0.65),.init(x:0.8,y:0.65)])
    let stroke=try #require(store.selectedDrawing?.strokes.first)
    store.selectDrawingStroke(stroke.id)
    store.moveDrawingPoint(.init(x:0.85,y:0.62),index:1)
    store.editDrawingStroke{$0.width=0.035}
    let edited=store.document;try edited.validate()
    let package=root.appendingPathComponent("Creative.lifeedit")
    try ProjectPackage.collect(edited,to:package)
    try FileManager.default.removeItem(at:imageURL)
    let reopened=try ProjectPackage.read(from:package)
    #expect(reopened.sequence==edited.sequence);#expect(ProjectPackage.missingAssets(in:reopened).isEmpty)
    let prepared=try await pipeline.prepare(.init(document:reopened))
    let preview=AVAssetImageGenerator(asset:prepared.playerItem.asset);preview.videoComposition=prepared.playerItem.videoComposition
    preview.requestedTimeToleranceBefore = .zero;preview.requestedTimeToleranceAfter = .zero
    let destination=root.appendingPathComponent("creative.mov")
    try await pipeline.export(.init(document:reopened),to:destination,options:.init(format:.proRes))
    let generator=AVAssetImageGenerator(asset:AVURLAsset(url:destination));generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
    func pixels(_ image:CGImage)->[UInt8] {
        var bytes=[UInt8](repeating:0,count:width*height*4)
        bytes.withUnsafeMutableBytes{memory in
            let context=CGContext(data:memory.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        };return bytes
    }
    for tick in [2,7] {
        let time=CMTime(value:Int64(tick),timescale:4)
        let live=pixels(try await preview.image(at:time).image),offline=pixels(try await generator.image(at:time).image)
        let error=zip(live,offline).reduce(0.0){$0+Double(abs(Int($1.0)-Int($1.1)))}/Double(live.count)
        #expect(error<5)
    }
    var clean=reopened;clean.sequence.tracks.removeAll{$0.kind == .caption || $0.kind == .drawing}
    let cleanPrepared=try await pipeline.prepare(.init(document:clean)),cleanGenerator=AVAssetImageGenerator(asset:cleanPrepared.playerItem.asset)
    cleanGenerator.videoComposition=cleanPrepared.playerItem.videoComposition
    let sampleTime=CMTime(value:7,timescale:4),output=try await generator.image(at:sampleTime).image
    let base=pixels(try await cleanGenerator.image(at:sampleTime).image),finished=pixels(output)
    let changed=stride(from:0,to:base.count,by:4).filter{abs(Int(base[$0])-Int(finished[$0]))>20}.count
    #expect(changed>100)
    let png=root.appendingPathComponent("creative.png")
    let writer=try #require(CGImageDestinationCreateWithURL(png as CFURL,UTType.png.identifier as CFString,1,nil))
    CGImageDestinationAddImage(writer,output,nil);#expect(CGImageDestinationFinalize(writer))
}
