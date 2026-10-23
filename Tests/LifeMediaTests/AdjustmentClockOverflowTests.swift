import Foundation
import Testing
@preconcurrency import AVFoundation
import CoreImage
import LifeCore
@testable import LifeMedia

@MainActor @Test func adjustmentClockValidRationalOverflowUsesEffectSecondsWithoutChangingTiming()async throws {
    let time=RationalTime(value:1001,timescale:240000),sourceStart=RationalTime(value:80000*999999937+1,timescale:999999937)
    let effects=[EffectInstance(stableID:"life.filter.VHS",parameters:["grain":1],seed:123)]
    let adjustment=Clip(duration:.init(value:20,timescale:1),sourceStart:sourceStart,effects:effects,audioEnabled:false)
    let base=Clip(duration:.init(value:20,timescale:1),graphic:.shape(.init(kind:.rectangle,rect:.init(x:0,y:0,width:1,height:1),fill:.init(red:0.6,green:0.2,blue:0.1),strokeWidth:0)))
    let settings=ProjectSettings(width:64,height:64,frameRate:.init(numerator:240000,denominator:1001))
    let document=ProjectDocument(sequence:Sequence(settings:settings,tracks:[Track(name:"Base",kind:.shape,clips:[base]),Track(name:"Adjust",kind:.adjustment,clips:[adjustment])]))
    try document.validate();try AdjustmentLayers.validate(in:document)
    #expect(throws:(any Error).self){try adjustment.checkedSourceTime(at:time)}
    let seconds=try #require(RenderClock.sourceSeconds(for:adjustment,at:time))
    let expectedSeconds=80000+1.0/999999937+1001.0/240000
    #expect(abs(seconds-expectedSeconds)<0.00000001)
    let pipeline=MediaPipeline()
    func frame(_ document:ProjectDocument)async throws->CGImage {
        let prepared=try await pipeline.prepare(ProjectSnapshot(document:document)),generator=AVAssetImageGenerator(asset:prepared.playerItem.asset)
        generator.videoComposition=prepared.playerItem.videoComposition;generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at:CMTime(value:time.value,timescale:Int32(time.timescale))).image
    }
    var baseline=document;baseline.sequence.tracks.removeLast()
    let source=CIImage(cgImage:try await frame(baseline)),actual=try await frame(document),context=CIContext(),canvas=CGRect(x:0,y:0,width:64,height:64)
    let expected=EffectRenderer.apply(effects,to:source,timeSeconds:expectedSeconds),wrong=EffectRenderer.apply(effects,to:source,timeSeconds:time.seconds)
    func bytes(_ image:CIImage)->[UInt8]{var result=[UInt8](repeating:0,count:64*64*4);context.render(image,toBitmap:&result,rowBytes:64*4,bounds:canvas,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB));return result}
    let a=bytes(CIImage(cgImage:actual)),b=bytes(expected),c=bytes(wrong)
    let correctError=zip(a,b).reduce(0){$0+abs(Int($1.0)-Int($1.1))},wrongError=zip(a,c).reduce(0){$0+abs(Int($1.0)-Int($1.1))}
    #expect(correctError<wrongError)
    let rational=EffectRenderer.apply(effects,to:source,time:.init(value:3,timescale:2)),scalar=EffectRenderer.apply(effects,to:source,timeSeconds:1.5)
    let rationalBytes=bytes(rational),scalarBytes=bytes(scalar)
    #expect(rationalBytes==scalarBytes)
    #expect(document.sequence.tracks[1].clips[0].sourceStart==sourceStart)
}

@Test func renderClockRejectsInvalidSpeedBeforeCheckedIntegerConversion() {
    var clip=Clip(duration:.init(value:1,timescale:1))
    for speed in [Double.nan,Double.infinity,Double.greatestFiniteMagnitude,0,4.1] {
        clip.speed=speed
        #expect(RenderClock.sourceSeconds(for:clip,at:.zero)==nil)
    }
}
