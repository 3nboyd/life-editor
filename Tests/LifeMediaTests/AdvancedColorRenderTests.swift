import Foundation
import AppKit
import Testing
@preconcurrency import AVFoundation
import CoreImage
import LifeCore
@testable import LifeMedia

@MainActor struct AdvancedColorRenderTests {
    private func pixel(_ image:CIImage)->[Float]{
        var bytes=[Float](repeating:0,count:4)
        CIContext(options:[.workingColorSpace:CGColorSpace(name:CGColorSpace.linearSRGB)!]).render(image,toBitmap:&bytes,rowBytes:16,bounds:CGRect(x:0,y:0,width:1,height:1),format:.RGBAf,colorSpace:CGColorSpace(name:CGColorSpace.linearSRGB));return bytes
    }
    @Test func advancedColorKernelsAreNeutralSelectiveAndPreserveAlpha()throws {
        let source=CIImage(color:CIColor(red:0.4,green:0.2,blue:0.1,alpha:0.5)).cropped(to:CGRect(x:0,y:0,width:4,height:4)),before=pixel(source)
        for definition in NativeEffectRegistry.advancedAdjustments {#expect(pixel(EffectRenderer.apply([NativeEffectRegistry.make(definition.stableID)],to:source))==before)}
        var curve=NativeEffectRegistry.make("life.adjust.curves");curve.parameters["red1"]=0.8;curve.parameters["red2"]=0.9
        let curved=pixel(EffectRenderer.apply([curve],to:source));#expect(curved[0]>before[0]+0.05);#expect(abs(curved[1]-before[1])<0.0001);#expect(abs(curved[3]-0.5)<0.0001)
        var levels=NativeEffectRegistry.make("life.adjust.levels");levels.parameters["gamma"]=2
        let lifted=pixel(EffectRenderer.apply([levels],to:source));#expect(lifted[0]>before[0]);#expect(lifted[1]>before[1]);#expect(lifted[3]==before[3])
        var hsl=NativeEffectRegistry.make("life.adjust.hsl");hsl.parameters["redHue"]=60
        let red=CIImage(color:CIColor(red:0.8,green:0.05,blue:0.05,alpha:0.5)).cropped(to:source.extent),blue=CIImage(color:CIColor(red:0.05,green:0.05,blue:0.8,alpha:0.5)).cropped(to:source.extent)
        let changed=pixel(EffectRenderer.apply([hsl],to:red));#expect(changed[1]>pixel(red)[1]+0.1);#expect(changed[3]==pixel(red)[3])
        var desaturate=NativeEffectRegistry.make("life.adjust.hsl");desaturate.parameters["redSaturation"] = -1
        let gray=pixel(EffectRenderer.apply([desaturate],to:red));#expect(abs(gray[0]-gray[1])<0.0001 && abs(gray[1]-gray[2])<0.0001)
        var lighten=NativeEffectRegistry.make("life.adjust.hsl");lighten.parameters["redLightness"]=0.4
        #expect(pixel(EffectRenderer.apply([lighten],to:red))[1]>pixel(red)[1])
        var master=NativeEffectRegistry.make("life.adjust.curves");master.parameters["master1"]=0.7
        let all=pixel(EffectRenderer.apply([master],to:source));#expect(all[1]>before[1]);#expect(all[2]>before[2])
        let unaffected=pixel(EffectRenderer.apply([hsl],to:blue));for (left,right) in zip(unaffected,pixel(blue)){#expect(abs(left-right)<0.0001)}
        var bypass=curve;bypass.isEnabled=false;#expect(pixel(EffectRenderer.apply([bypass],to:source))==before)
        curve.strength=0.5;let half=pixel(EffectRenderer.apply([curve],to:source));#expect(half[0]>before[0] && half[0]<curved[0])
    }
    @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"]=="1"))
    func advancedColorAdjustmentLayerMatchesNativeExport()async throws {
        _ = NSApplication.shared
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("life-advanced-color-"+UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        var effects=NativeEffectRegistry.advancedAdjustments.map{NativeEffectRegistry.make($0.stableID)};effects[0].parameters["red2"]=0.7;effects[1].parameters["gamma"]=1.2;effects[2].parameters["redHue"]=20
        let base=Clip(duration:.init(value:1,timescale:1),title:.init(text:"Color",fontSize:28,style:.init(color:.init(red:0.8,green:0.1,blue:0.1)))),adjustment=Clip(duration:.init(value:1,timescale:1),effects:effects)
        let document=ProjectDocument(sequence:.init(settings:.init(width:160,height:120),tracks:[.init(name:"Text",kind:.title,clips:[base]),.init(name:"Grade",kind:.adjustment,clips:[adjustment])]))
        let package=root.appendingPathComponent("Color.lifeedit");try ProjectPackage.write(document,to:package);let reopened=try ProjectPackage.read(from:package);#expect(reopened==document)
        let snapshot=ProjectSnapshot(document:reopened),pipeline=MediaPipeline(),prepared=try await pipeline.prepare(snapshot),preview=AVAssetImageGenerator(asset:prepared.playerItem.asset);preview.videoComposition=prepared.playerItem.videoComposition
        let url=root.appendingPathComponent("color.mov");try await pipeline.export(snapshot,to:url,options:.init(format:.proRes))
        let decoded=AVAssetImageGenerator(asset:AVURLAsset(url:url)),time=CMTime(value:1,timescale:2)
        let a=try await preview.image(at:time).image,b=try await decoded.image(at:time).image
        func bytes(_ image:CGImage)->[UInt8]{var result=[UInt8](repeating:0,count:160*120*4);CIContext().render(CIImage(cgImage:image),toBitmap:&result,rowBytes:160*4,bounds:CGRect(x:0,y:0,width:160,height:120),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB));return result}
        let before=bytes(a),after=bytes(b),difference=zip(before,after).reduce(0.0){$0+Double(abs(Int($1.0)-Int($1.1)))}/Double(before.count);#expect(difference<4)
    }
}
