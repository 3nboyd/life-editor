import Testing
@preconcurrency import AVFoundation
import CoreImage
import LifeCore
@testable import LifeMedia
private let tonalIDs=["life.adjust.whites","life.adjust.blackPoint","life.adjust.brilliance"]
private func toneEffect(_ id:String,_ value:Double,strength:Double=1)->EffectInstance{EffectInstance(stableID:id,parameters:["value":value],strength:strength)}
private func toneImage(_ row:[Float],alpha:Float=1)->CIImage{
    var values=[Float]();for _ in 0..<16{for value in row{values.append(contentsOf:[value*alpha,value*alpha,value*alpha,alpha])}}
    let data=values.withUnsafeBytes{Data($0)}
    return CIImage(bitmapData:data,bytesPerRow:row.count*16,size:CGSize(width:row.count,height:16),format:.RGBAf,colorSpace:CGColorSpace(name:CGColorSpace.linearSRGB))
}
private func tonePixels(_ image:CIImage)->[Float]{
    let width=Int(image.extent.width),height=Int(image.extent.height);var values=[Float](repeating:0,count:width*height*4)
    let space=CGColorSpace(name:CGColorSpace.linearSRGB)!,context=CIContext(options:[.workingColorSpace:space,.outputColorSpace:space])
    values.withUnsafeMutableBytes{context.render(image,toBitmap:$0.baseAddress!,rowBytes:width*16,bounds:image.extent,format:.RGBAf,colorSpace:space)};return values
}
@Test func tonalControlsNeutralPolaritySelectiveRangesAndPremultipliedAlpha(){
    let image=toneImage((0...100).map{Float($0)/100},alpha:0.35),base=tonePixels(image),width=101
    func red(_ pixels:[Float],_ x:Int)->Float{pixels[(8*width+x)*4]}
    for id in tonalIDs{
        #expect(tonePixels(EffectRenderer.apply([toneEffect(id,0)],to:image))==base)
        #expect(tonePixels(EffectRenderer.apply([toneEffect(id,1,strength:0)],to:image))==base)
        var bypass=toneEffect(id,1);bypass.isEnabled=false;#expect(tonePixels(EffectRenderer.apply([bypass],to:image))==base)
        for value in [-1.0,1.0]{
            let result=EffectRenderer.apply([toneEffect(id,value)],to:image),pixels=tonePixels(result)
            #expect(result.extent==image.extent)
            for offset in stride(from:0,to:pixels.count,by:4){
                #expect(pixels[offset].isFinite && pixels[offset]>=0 && pixels[offset]<=0.35001)
                #expect(abs(pixels[offset+3]-0.35)<0.00001)
            }
        }
    }
    let whites=tonePixels(EffectRenderer.apply([toneEffect(tonalIDs[0],1)],to:image)),black=tonePixels(EffectRenderer.apply([toneEffect(tonalIDs[1],1)],to:image))
    #expect(abs(red(whites,20)-red(base,20))<0.00001);#expect(red(whites,90)>red(base,90)+0.02)
    #expect(abs(red(black,90)-red(base,90))<0.00001);#expect(red(black,10)<red(base,10)-0.01)
    #expect(red(tonePixels(EffectRenderer.apply([toneEffect(tonalIDs[0],-1)],to:image)),90)<red(base,90))
    #expect(red(tonePixels(EffectRenderer.apply([toneEffect(tonalIDs[1],-1)],to:image)),10)>red(base,10))
    let clear=tonePixels(EffectRenderer.apply([toneEffect(tonalIDs[2],1)],to:toneImage([0.2,0.8],alpha:0)))
    #expect(clear.allSatisfy{$0==0})
}
@Test func brillianceUsesLocalDetailWithoutExpandingEdgesAndThumbnailsRenderRealEffects()async throws{
    let row=[Float](repeating:0.3,count:20)+[Float](repeating:0.5,count:20),image=toneImage(row)
    let positive=tonePixels(EffectRenderer.apply([toneEffect(tonalIDs[2],1)],to:image)),negative=tonePixels(EffectRenderer.apply([toneEffect(tonalIDs[2],-1)],to:image))
    let left=(8*40+19)*4,right=(8*40+20)*4
    #expect(positive[right]-positive[left]>negative[right]-negative[left]+0.01)
    let base=try await EffectThumbnails.shared.image(effects:[])
    func bytes(_ image:CGImage)->Data{image.dataProvider!.data! as Data}
    for id in tonalIDs{
        let actual=try await EffectThumbnails.shared.image(effects:[toneEffect(id,0.8)])
        #expect(actual.width==base.width && actual.height==base.height);#expect(bytes(actual) != bytes(base))
        #expect(bytes(actual)==bytes(try await EffectThumbnails.shared.image(effects:[toneEffect(id,0.8)])))
    }
}
@MainActor @Test func tonalControlsMatchNativePreviewExportForClipsAndAdjustmentLayers()async throws{
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:directory)}
    let graphic=Clip(duration:.init(value:1,timescale:1),graphic:.shape(.init(kind:.rectangle,rect:.init(x:0,y:0,width:1,height:1),fill:.init(red:0.7,green:0.5,blue:0.3),strokeWidth:0)))
    let effects=[toneEffect(tonalIDs[0],0.6,strength:0.7),toneEffect(tonalIDs[1],-0.4),toneEffect(tonalIDs[2],0.8)]
    for adjustment in [false,true]{
        var document=ProjectDocument(sequence:Sequence(settings:ProjectSettings(width:64,height:64),tracks:[Track(name:"Picture",kind:.shape,clips:[graphic])]))
        if adjustment{document=try AdjustmentLayers.adding(at:.zero,duration:graphic.duration,in:document);document.sequence.tracks[1].clips[0].effects=effects}else{document.sequence.tracks[0].clips[0].effects=effects}
        let package=directory.appendingPathComponent("tone-\(adjustment).lifeedit");try ProjectPackage.write(document,to:package);let reopened=try ProjectPackage.read(from:package);#expect(reopened==document)
        let pipeline=MediaPipeline(),prepared=try await pipeline.prepare(.init(document:reopened)),preview=AVAssetImageGenerator(asset:prepared.playerItem.asset)
        preview.videoComposition=prepared.playerItem.videoComposition;let time=CMTime(value:1,timescale:2),a=try await preview.image(at:time).image
        let url=directory.appendingPathComponent("tone-\(adjustment).mov");try await pipeline.export(.init(document:reopened),to:url,options:.init(format:.proRes))
        let b=try await AVAssetImageGenerator(asset:AVURLAsset(url:url)).image(at:time).image
        func pixel(_ image:CGImage)->[UInt8]{var values=[UInt8](repeating:0,count:4);values.withUnsafeMutableBytes{let context=CGContext(data:$0.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;context.draw(image,in:CGRect(x:-32,y:-32,width:64,height:64))};return values}
        let p=pixel(a),q=pixel(b);for channel in 0..<3{#expect(abs(Int(p[channel])-Int(q[channel]))<20)}
    }
}
