import Foundation
import Testing
import CoreGraphics
import LifeCore
@testable import LifeMedia

@Test func adjustmentFallbackThumbnailsRenderRealDeterministicEffects()async throws {
    func pixels(_ image:CGImage)->[UInt8]{
        var bytes=[UInt8](repeating:0,count:image.width*image.height*4)
        let context=CGContext(data:&bytes,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height));return bytes
    }
    let base=pixels(try await EffectThumbnails.shared.image(effects:[]))
    let gray=[NativeEffectRegistry.make("life.filter.grayscale")]
    let result=pixels(try await EffectThumbnails.shared.image(effects:gray))
    #expect(result != base)
    var grayChannels=true
    for index in stride(from:0,to:result.count,by:4){
        let red=Int(result[index]),green=Int(result[index+1]),blue=Int(result[index+2])
        if abs(red-green)>=2 || abs(green-blue)>=2{grayChannels=false;break}
    }
    #expect(grayChannels)
    #expect(result==pixels(try await EffectThumbnails.shared.image(effects:gray)))
    for definition in NativeEffectRegistry.definitions{let image=try await EffectThumbnails.shared.image(effects:[NativeEffectRegistry.make(definition.stableID,seed:17)]);#expect(image.width==256 && image.height==144)}
}
