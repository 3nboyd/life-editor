import Foundation
import Testing
@preconcurrency import AVFoundation
import CoreImage
import ImageIO
import LifeCore
@testable import LifeMedia

@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"]=="1"))
func cropFitFillAndStraightenMatchDecodedExportAfterUndoAndReopen() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("life-crop-\(UUID())")
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:directory)}
    let sourceURL=directory.appendingPathComponent("white.png")
    let context=try #require(CGContext(data:nil,width:200,height:100,bitsPerComponent:8,bytesPerRow:800,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray:1,alpha:1));context.fill(CGRect(x:0,y:0,width:200,height:100))
    let image=try #require(context.makeImage()),destination=try #require(CGImageDestinationCreateWithURL(sourceURL as CFURL,"public.png" as CFString,1,nil))
    CGImageDestinationAddImage(destination,image,nil);try #require(CGImageDestinationFinalize(destination))
    let media=MediaPipeline(),asset=try await media.probe(sourceURL).asset
    let clip=Clip(assetID:asset.id,duration:.init(value:1,timescale:1))
    let original=ProjectDocument(sequence:.init(settings:.init(width:100,height:100),tracks:[.init(name:"Image",kind:.image,clips:[clip])]),assets:[asset])
    let canvas=CropSize(width:100,height:100),source=CropSize(width:200,height:100)
    func pixels(_ image:CGImage)->[UInt8] {
        var bytes=[UInt8](repeating:0,count:image.width*image.height*4)
        let context=CGContext(data:&bytes,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height));return bytes
    }
    for mode in [CropFitMode.fit,.fill] {
        var visual=try CropGeometry.applying(.landscape,to:.init(rotationDegrees:30,cropLeft:0.2,cropRight:0.05),source:source)
        visual=try CropGeometry.placing(visual,source:source,canvas:canvas,mode:mode)
        var edited=original;edited.sequence.tracks[0].clips[0].visual=visual
        let editor=ProjectEditor(document:original);try editor.perform(.replace(edited));editor.undo();#expect(editor.document==original);editor.redo()
        let name=mode == .fit ? "fit":"fill",package=directory.appendingPathComponent("\(name).lifeedit")
        try ProjectPackage.write(editor.document,to:package);let reopened=try ProjectPackage.read(from:package)
        #expect(reopened==edited);#expect(reopened.sequence.settings==original.sequence.settings)
        let snapshot=ProjectSnapshot(document:reopened),prepared=try await media.prepare(snapshot)
        let preview=AVAssetImageGenerator(asset:prepared.playerItem.asset);preview.videoComposition=prepared.playerItem.videoComposition
        let before=pixels(try await preview.image(at:CMTime(value:1,timescale:2)).image)
        let output=directory.appendingPathComponent("\(name).mp4");try await media.export(snapshot,to:output)
        let after=pixels(try await AVAssetImageGenerator(asset:AVURLAsset(url:output)).image(at:CMTime(value:1,timescale:2)).image)
        for (x,y) in [(3,3),(96,3),(3,96),(96,96)] {
            let index=(y*100+x)*4
            if mode == .fit {#expect(before[index]<5 && after[index]<8)}
            else {#expect(before[index]>245 && after[index]>235)}
        }
        let meanDifference=zip(before,after).reduce(0.0){$0+Double(abs(Int($1.0)-Int($1.1)))}/Double(before.count)
        #expect(meanDifference<5)
    }
    // Check crop-center compensation using the actual shared transform, including flips.
    let input=CIImage(color:.white).cropped(to:CGRect(x:0,y:25,width:100,height:50))
    let visual=try CropGeometry.placing(.init(rotationDegrees:90,cropLeft:0.1,cropRight:0.3,flipHorizontal:true),source:source,canvas:canvas,mode:.fit)
    let extent=EffectRenderer.transform(input,visual:visual,canvas:CGRect(x:0,y:0,width:100,height:100)).extent
    #expect(abs(extent.midX-50)<0.0001 && abs(extent.midY-50)<0.0001)
}
