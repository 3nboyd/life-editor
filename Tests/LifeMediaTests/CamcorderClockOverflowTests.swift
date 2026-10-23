import Foundation
import Testing
@preconcurrency import AVFoundation
import CoreImage
import LifeCore
@testable import LifeMedia

@MainActor @Test func camcorderDateClockHandlesValidIncommensurateTimesWithoutRationalOverflow()async throws {
    let time=RationalTime(value:1001,timescale:30000)
    let sourceStart=RationalTime(value:80000*999999937+1,timescale:999999937)
    let asset=MediaAsset(url:URL(fileURLWithPath:"/source.png"),kind:.image,duration:.init(value:80022,timescale:1))
    var clip=Clip(assetID:asset.id,duration:.init(value:20,timescale:1),sourceStart:sourceStart,speed:1.05)
    var document=ProjectDocument(sequence:Sequence(settings:ProjectSettings(width:320,height:180,frameRate:.init(numerator:30000,denominator:1001)),tracks:[Track(name:"Image",kind:.image,clips:[clip])]),assets:[asset])
    try document.validate()
    #expect(throws:(any Error).self){try clip.checkedSourceTime(at:time)}
    #expect(CamcorderDateRenderer.sourceSeconds(for:clip,at:time)==nil)
    var effect=NativeEffectRegistry.make("life.filter.VHS");effect.parameters["grain"]=0
    effect.camcorderDate=CamcorderDateOverlay.parse("2000-01-01T00:00:00Z")
    clip.effects=[effect]
    let clock=try #require(CamcorderDateRenderer.sourceSeconds(for:clip,at:time))
    #expect(abs(clock-(80000+1.0/999999937+1001.0/30000*1.05))<0.00000001)
    #expect(effect.camcorderDate?.text(atSourceSeconds:clock)=="2000-01-01 22:13:20")
    clip.effects?[0].isEnabled=false
    #expect(CamcorderDateRenderer.sourceSeconds(for:clip,at:time)==nil)
    clip.effects?[0].isEnabled=true;clip.effects?[0].strength=0
    #expect(CamcorderDateRenderer.sourceSeconds(for:clip,at:time)==nil)
    clip.effects?[0].strength=1;clip.effects?[0].camcorderDate?.enabled=false
    #expect(CamcorderDateRenderer.sourceSeconds(for:clip,at:time)==nil)
    document.sequence.tracks[0].clips[0]=clip;try document.validate()
}

@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"]=="1"))
func camcorderDateNativeCompositorSurvivesLargeSourceClockWithAndWithoutOverlay()async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("life-clock-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:directory)}
    let url=directory.appendingPathComponent("source.png"),context=CIContext(),canvas=CGRect(x:0,y:0,width:320,height:180)
    let source=CIImage(color:CIColor(red:0.1,green:0.1,blue:0.1)).cropped(to:canvas)
    try context.writePNGRepresentation(of:source,to:url,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!)
    let asset=MediaAsset(url:url,kind:.image,duration:.init(value:80022,timescale:1))
    var clip=Clip(assetID:asset.id,duration:.init(value:20,timescale:1),sourceStart:.init(value:80000*999999937+1,timescale:999999937),speed:1.05)
    let settings=ProjectSettings(width:320,height:180,frameRate:.init(numerator:30000,denominator:1001)),pipeline=MediaPipeline()
    func render(_ clip:Clip)async throws->CGImage {
        let document=ProjectDocument(sequence:Sequence(settings:settings,tracks:[Track(name:"Image",kind:.image,clips:[clip])]),assets:[asset])
        try document.validate()
        let prepared=try await pipeline.prepare(ProjectSnapshot(document:document))
        let generator=AVAssetImageGenerator(asset:prepared.playerItem.asset);generator.videoComposition=prepared.playerItem.videoComposition
        generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at:CMTime(value:1001,timescale:30000)).image
    }
    let plain=try await render(clip)
    var effect=NativeEffectRegistry.make("life.filter.VHS");effect.parameters["grain"]=0
    effect.camcorderDate=CamcorderDateOverlay.parse("2000-01-01T00:00:00Z");clip.effects=[effect]
    let dated=try await render(clip)
    func bytes(_ image:CGImage)->[UInt8]{var result=[UInt8](repeating:0,count:320*180*4);context.render(CIImage(cgImage:image),toBitmap:&result,rowBytes:320*4,bounds:canvas,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB));return result}
    let plainBytes=bytes(plain),datedBytes=bytes(dated)
    #expect(!plainBytes.contains{$0>240 && $0<255})
    let expected=EffectRenderer.apply([effect],to:source,time:.init(value:1001,timescale:30000),sourceSeconds:80000+1001.0/30000*1.05)
    let wrong=EffectRenderer.apply([effect],to:source,time:.init(value:1001,timescale:30000),sourceSeconds:1001.0/30000)
    let expectedBytes=bytes(try #require(context.createCGImage(expected,from:canvas))),wrongBytes=bytes(try #require(context.createCGImage(wrong,from:canvas)))
    let expectedError=zip(datedBytes,expectedBytes).reduce(0){$0+abs(Int($1.0)-Int($1.1))}
    let wrongError=zip(datedBytes,wrongBytes).reduce(0){$0+abs(Int($1.0)-Int($1.1))}
    #expect(expectedError<wrongError)
}
