import Foundation
import Testing
@preconcurrency import AVFoundation
import CoreImage
import LifeCore
@testable import LifeMedia

@MainActor struct TextPresetRenderTests {
    private func pixels(_ image:CGImage)->[UInt8]{
        var bytes=[UInt8](repeating:0,count:image.width*image.height*4)
        let context=CGContext(data:&bytes,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height));return bytes
    }
    @Test func eightActualTitleThumbnailsAreDistinctDeterministicAndNeonHasAlphaHalo()async throws {
        var seen=Set<Data>()
        for family in TextFamily.allCases {
            let first=try await TitleThumbnails.shared.image(for:family)
            let bytes=pixels(first)
            #expect(bytes==pixels(try await TitleThumbnails.shared.image(for:family)))
            seen.insert(Data(bytes))
        }
        #expect(seen.count==8)
        let clip=try TextPresets.applying(.neon,to:Clip(duration:.init(value:1,timescale:1),title:.init(text:"Life",fontSize:48,style:.init(x:0.5,y:0.5))))
        let canvas=CGRect(x:0,y:0,width:240,height:100)
        let title=try #require(clip.title),image=try #require(TitleRenderer.image(title,size:canvas.size))
        let context=CIContext(),base=pixels(try #require(context.createCGImage(image,from:canvas)))
        let glow=pixels(try #require(context.createCGImage(EffectRenderer.apply(clip.effects ?? [],to:image).cropped(to:canvas),from:canvas)))
        let halo=stride(from:0,to:base.count,by:4).filter{base[$0+3]==0 && glow[$0+3]>4}
        #expect(halo.count>100)
    }
    @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"]=="1"))
    func textFamilyUndoPackagePreviewAndDecodedExportMatch()async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("life-text-presets-\(UUID())")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:directory)}
        let pipeline=MediaPipeline(),clip=Clip(duration:.init(value:1,timescale:1),title:.init(text:"Life",fontSize:32,style:.init(x:0.5,y:0.5),animation:.init(kind:.fade,duration:0.2)))
        let original=ProjectDocument(sequence:.init(settings:.init(width:128,height:96),tracks:[.init(name:"Text",kind:.title,clips:[clip])]))
        for family in TextFamily.allCases {
            var next=original;next.sequence.tracks[0].clips[0]=try TextPresets.applying(family,to:clip)
            let editor=ProjectEditor(document:original);try editor.perform(.replace(next));editor.undo();#expect(editor.document==original);editor.redo()
            let package=directory.appendingPathComponent(family.rawValue+".lifeedit");try ProjectPackage.write(editor.document,to:package)
            let reopened=try ProjectPackage.read(from:package);#expect(reopened==next)
            let snapshot=ProjectSnapshot(document:reopened),prepared=try await pipeline.prepare(snapshot)
            let preview=AVAssetImageGenerator(asset:prepared.playerItem.asset);preview.videoComposition=prepared.playerItem.videoComposition
            let before=pixels(try await preview.image(at:CMTime(value:1,timescale:2)).image)
            let output=directory.appendingPathComponent(family.rawValue+".mp4");try await pipeline.export(snapshot,to:output)
            let after=pixels(try await AVAssetImageGenerator(asset:AVURLAsset(url:output)).image(at:CMTime(value:1,timescale:2)).image)
            let difference=zip(before,after).reduce(0.0){$0+Double(abs(Int($1.0)-Int($1.1)))}/Double(before.count)
            #expect(difference<5)
            #expect(before.contains{$0>0})
        }
    }
}
