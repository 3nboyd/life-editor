import Foundation
import CoreImage
import LifeCore

/// Original color/gray chart for browsing looks on generated objects and
/// adjustment layers. Every thumbnail runs the actual shared effect graph.
public actor EffectThumbnails {
    public static let shared=EffectThumbnails()
    private let context=CIContext(options:[.workingColorSpace:CGColorSpace(name:CGColorSpace.linearSRGB)!])
    public func image(effects:[EffectInstance])throws->CGImage {
        try Task.checkCancellation()
        let canvas=CGRect(x:0,y:0,width:256,height:144)
        var image=CIImage(color:CIColor(red:0.15,green:0.18,blue:0.22)).cropped(to:canvas)
        let colors:[CIColor]=[.init(red:0.85,green:0.22,blue:0.18),.init(red:0.95,green:0.65,blue:0.18),.init(red:0.24,green:0.7,blue:0.35),.init(red:0.18,green:0.48,blue:0.85),.init(red:0.62,green:0.25,blue:0.76),.init(red:0.72,green:0.49,blue:0.35),.init(red:0.36,green:0.24,blue:0.18),.init(red:0.86,green:0.78,blue:0.65)]
        for (index,color) in colors.enumerated(){image=CIImage(color:color).cropped(to:CGRect(x:(index%4)*64,y:48+(index/4)*48,width:64,height:48)).composited(over:image)}
        for index in 0..<32{let value=Double(index)/31;image=CIImage(color:CIColor(red:value,green:value,blue:value)).cropped(to:CGRect(x:index*8,y:0,width:8,height:48)).composited(over:image)}
        image=EffectRenderer.apply(effects,to:image,time:.zero).cropped(to:canvas)
        try Task.checkCancellation()
        guard let result=context.createCGImage(image,from:canvas,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)) else{throw MediaError.exportUnavailable}
        return result
    }
}
