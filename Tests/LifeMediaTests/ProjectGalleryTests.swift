import Foundation
import Testing
@preconcurrency import AVFoundation
import AppKit
import ImageIO
import LifeCore
@testable import LifeMedia

/// Opt-in, reproducible product-output examples. Every published pixel comes
/// from a decoded export; this test never captures or reconstructs application UI.
@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_GENERATE_PROJECT_GALLERY"]=="1"))
func generateRenderedProjectGallery() async throws {
    _ = NSApplication.shared
    let repository=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source=repository.appendingPathComponent("docs/gallery/source/rehearsal.png")
    let output=URL(fileURLWithPath:ProcessInfo.processInfo.environment["LIFE_GALLERY_OUTPUT"] ?? "/tmp/life-editor-gallery",isDirectory:true)
    try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
    let pipeline=MediaPipeline(),probe=try await pipeline.probe(source)
    let duration=RationalTime(value:1,timescale:1)
    for portrait in [false,true] {
        let name=portrait ? "social":"performance",width=portrait ? 720:1280,height=portrait ? 1280:720
        let visual=try CropGeometry.placing(.init(),source:.init(width:Double(probe.width),height:Double(probe.height)),canvas:.init(width:Double(width),height:Double(height)),mode:.fill)
        let photo=Clip(name:"Rehearsal",assetID:probe.asset.id,duration:duration,effects:[NativeEffectRegistry.make(portrait ? "life.filter.clean":"life.filter.LA",strength:portrait ? 0.65:0.4)],visual:visual)
        let title=TitleContent(text:portrait ? "one more\ntake.":"ROOM SESSIONS",fontSize:portrait ? 76:52,
            style:.init(fontName:"Helvetica-Bold",x:portrait ? 0.5:0.3,y:portrait ? 0.18:0.84,
                        background:portrait ? .clear:.init(red:0.035,green:0.045,blue:0.05,alpha:0.88),
                        backgroundStyle:.init(shape:portrait ? .none:.rounded,padding:18,cornerRadius:0.2)),
            animation:.init(kind:.fade,duration:0.3))
        let titleClip=Clip(name:"Title",duration:duration,title:title)
        let positionedTitle=portrait ? titleClip:try TitleLayoutPreset.lowerThird.applying(to:titleClip,canvasHeight:height)
        var tracks:[Track]=[.init(name:"Rehearsal",kind:.image,clips:[photo]),.init(name:"Title",kind:.title,clips:[positionedTitle])]
        if portrait {
            let cue=try #require(SRT.parse("1\n00:00:00,000 --> 00:00:01,000\nStay for the chorus.\n").first)
            var caption=cue.clip
            caption.title?.fontSize=34
            caption.title?.style = .init(fontName:"Helvetica-Bold",x:0.5,y:0.82,background:.init(red:0.035,green:0.045,blue:0.05,alpha:0.9),backgroundStyle:.init(shape:.pill,padding:18))
            tracks.append(.init(name:"Captions",kind:.caption,clips:[caption]))
        }
        let document=ProjectDocument(name:portrait ? "One more take":"Room sessions",sequence:.init(settings:.init(width:width,height:height),tracks:tracks),assets:[probe.asset])
        let package=output.appendingPathComponent(name+".lifeedit")
        // Collection refuses existing destinations, preserving any user edits.
        try ProjectPackage.collect(document,to:package)
        let reopened=try ProjectPackage.read(from:package)
        #expect(ProjectPackage.missingAssets(in:reopened).isEmpty)
        #expect(reopened.sequence==document.sequence)
        let snapshot=ProjectSnapshot(document:reopened)
        let playback=try await pipeline.prepare(snapshot)
        let preview=AVAssetImageGenerator(asset:playback.playerItem.asset)
        preview.videoComposition=playback.playerItem.videoComposition
        preview.requestedTimeToleranceBefore = .zero;preview.requestedTimeToleranceAfter = .zero
        let movie=output.appendingPathComponent(name+".mov")
        try await pipeline.export(snapshot,to:movie,options:.init(format:.proRes))
        let generator=AVAssetImageGenerator(asset:AVURLAsset(url:movie))
        generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
        let time=CMTime(value:3,timescale:4)
        let frame=try await generator.image(at:time).image
        #expect(frame.width==width && frame.height==height)
        let before=try await preview.image(at:time).image
        func pixels(_ image:CGImage)->[UInt8] {
            var bytes=[UInt8](repeating:0,count:width*height*4)
            let context=CGContext(data:&bytes,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height));return bytes
        }
        let difference=zip(pixels(before),pixels(frame)).reduce(0.0){$0+Double(abs(Int($1.0)-Int($1.1)))}/Double(width*height*4)
        #expect(difference<4)
        let destination=try #require(CGImageDestinationCreateWithURL(output.appendingPathComponent(name+".png") as CFURL,"public.png" as CFString,1,nil))
        CGImageDestinationAddImage(destination,frame,nil)
        try #require(CGImageDestinationFinalize(destination))
    }
}
