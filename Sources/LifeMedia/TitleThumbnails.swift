import Foundation
import CoreImage
import LifeCore

/// Background, serial thumbnail rendering through the same Core Text/effect graph
/// used by the composition renderer. No separate thumbnail typography exists.
public actor TitleThumbnails {
    public static let shared=TitleThumbnails()
    private let context=CIContext(options:[.workingColorSpace:CGColorSpace(name:CGColorSpace.linearSRGB)!])
    public func image(background:TitleBackgroundStyle,color:RGBAColor,width:Int=160,height:Int=90)throws->CGImage {
        try Task.checkCancellation()
        guard background.isValid,(32...1024).contains(width),(32...1024).contains(height) else{throw MediaError.invalidRange("Title background")}
        // Thumbnail units are scaled together, preserving the actual renderer's
        // border/shadow geometry rather than drawing a separate icon imitation.
        var appearance=background
        let scale=Double(height)/180
        appearance.padding *= scale;appearance.borderWidth *= scale;appearance.shadowBlur *= scale;appearance.shadowOffsetX *= scale;appearance.shadowOffsetY *= scale
        let title=TitleContent(text:"Life\nEditor",fontSize:Double(height)*0.22,style:.init(x:0.5,y:0.45,background:color,backgroundStyle:appearance))
        let canvas=CGRect(x:0,y:0,width:width,height:height)
        guard let image=TitleRenderer.image(title,size:canvas.size),let output=context.createCGImage(image,from:canvas,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)) else{throw MediaError.exportUnavailable}
        try Task.checkCancellation();return output
    }
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
