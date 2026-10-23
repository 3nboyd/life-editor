import Foundation
import CoreImage
import LifeCore

/// Background, serial thumbnail rendering through the same Core Text/effect graph
/// used by the composition renderer. No separate thumbnail typography exists.
public actor TitleThumbnails {
    public static let shared=TitleThumbnails()
    private let context=CIContext(options:[.workingColorSpace:CGColorSpace(name:CGColorSpace.linearSRGB)!])
    public func image(for family:TextFamily,width:Int=240,height:Int=100)throws->CGImage {
        try Task.checkCancellation()
        guard (32...1024).contains(width),(32...1024).contains(height) else{throw CropGeometryError.dimensions}
        let sample=Clip(duration:.init(value:1,timescale:1),title:.init(text:"Life",fontSize:Double(height)*0.48,style:.init(x:0.5,y:0.5)))
        let clip=try TextPresets.applying(family,to:sample)
        let canvas=CGRect(x:0,y:0,width:width,height:height)
        guard let title=clip.title,let image=TitleRenderer.image(title,size:canvas.size) else{throw MediaError.exportUnavailable}
        let rendered=EffectRenderer.apply(clip.effects ?? [],to:image).cropped(to:canvas)
        try Task.checkCancellation()
        guard let output=context.createCGImage(rendered,from:canvas,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)) else{throw MediaError.exportUnavailable}
        return output
    }
}
