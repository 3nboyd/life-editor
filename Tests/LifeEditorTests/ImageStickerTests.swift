import Testing
import AppKit
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import AVFoundation
import LifeCore
import LifeMedia
@testable import LifeEditor

@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"]=="1"))
func imageStickerPreservesAlphaTimingCollectionAndUndo()async throws {
    _ = NSApplication.shared
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("life-sticker-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:root)}
    func png(_ url:URL,sticker:Bool)throws{
        let context=try #require(CGContext(data:nil,width:160,height:90,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(sticker ? CGColor(red:1,green:0,blue:0,alpha:1):CGColor(red:0,green:0,blue:1,alpha:1))
        context.fill(sticker ? CGRect(x:60,y:25,width:40,height:40):CGRect(x:0,y:0,width:160,height:90))
        let destination=try #require(CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil))
        CGImageDestinationAddImage(destination,try #require(context.makeImage()),nil)
        #expect(CGImageDestinationFinalize(destination))
    }
    let background=root.appendingPathComponent("blue.png"),image=root.appendingPathComponent("sticker.png")
    try png(background,sticker:false);try png(image,sticker:true)
    let media=MediaPipeline(),baseAsset=try await media.probe(background).asset
    let initial=ProjectDocument(sequence:.init(settings:.init(width:160,height:90),tracks:[.init(name:"Base",kind:.image,clips:[.init(assetID:baseAsset.id,duration:.init(value:3,timescale:1))])]),assets:[baseAsset])
    let store=EditorStore();store.replace(initial);store.playheadTime = .init(value:1,timescale:1)
    try await store.insertImageSticker(from:image)
    let inserted=store.document,id=try #require(store.selection)
    #expect(inserted.sequence.settings==initial.sequence.settings)
    #expect(store.selectedClip?.start == .init(value:1,timescale:1))
    #expect(store.selectedClip?.visual == .init(scaleX:0.3,scaleY:0.3))
    #expect(inserted.assets.last?.url == image)
    store.undo();#expect(store.document==initial);store.redo();#expect(store.document==inserted)
    store.apply(.trim(clipID:id,start:.init(value:1,timescale:1),end:.init(value:2,timescale:1)))
    let edited=store.document,package=root.appendingPathComponent("Collected.lifeedit")
    try ProjectPackage.collect(edited,to:package)
    try FileManager.default.removeItem(at:image);try FileManager.default.removeItem(at:background)
    let reopened=try ProjectPackage.read(from:package)
    #expect(reopened.sequence==edited.sequence);#expect(ProjectPackage.missingAssets(in:reopened).isEmpty)
    let prepared=try await media.prepare(.init(document:reopened))
    let preview=AVAssetImageGenerator(asset:prepared.playerItem.asset);preview.videoComposition=prepared.playerItem.videoComposition
    let destination=root.appendingPathComponent("sticker.mov")
    try await media.export(.init(document:reopened),to:destination,options:.init(format:.proRes))
    let exported=AVAssetImageGenerator(asset:AVURLAsset(url:destination))
    for generator in [preview,exported]{generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero}
    func pixels(_ image:CGImage)->[UInt8]{
        var bytes=[UInt8](repeating:0,count:160*90*4)
        bytes.withUnsafeMutableBytes{memory in
            let context=CGContext(data:memory.baseAddress,width:160,height:90,bitsPerComponent:8,bytesPerRow:160*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:160,height:90))
        };return bytes
    }
    for numerator in [1,3,5]{
        let time=CMTime(value:Int64(numerator),timescale:2)
        let live=pixels(try await preview.image(at:time).image),offline=pixels(try await exported.image(at:time).image)
        #expect(zip(live,offline).reduce(0.0){$0+Double(abs(Int($1.0)-Int($1.1)))}/Double(live.count)<5)
        let center=(45*160+80)*4,transparent=(45*160+60)*4
        if numerator==3{#expect(offline[center]>200 && offline[center+2]<40)}
        else{#expect(offline[center]<40 && offline[center+2]>200)}
        // Inside the scaled PNG extent but outside its opaque red geometry.
        #expect(offline[transparent]<40 && offline[transparent+2]>200)
    }
}
