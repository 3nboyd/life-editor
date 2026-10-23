import Foundation
import CoreImage
import CoreText
import LifeCore

private final class CamcorderBitmapCache:@unchecked Sendable {
    let images=NSCache<NSString,CGImage>()
    init(){images.countLimit=16;images.totalCostLimit=16*1024*1024}
}
enum CamcorderDateRenderer {
    private static let cache=CamcorderBitmapCache()
    /// A display-only clock. Valid rational edit times can require an
    /// unrepresentable combined denominator; wall-clock formatting already uses
    /// Double, so fall back without changing any media/editing time mappings.
    static func sourceSeconds(for clip:Clip,at time:RationalTime)->Double? {
        guard (clip.effects ?? []).contains(where:{$0.isEnabled && $0.strength>0 && $0.stableID == "life.filter.VHS" && $0.camcorderDate?.enabled == true}) else{return nil}
        return RenderClock.sourceSeconds(for:clip,at:time)
    }
    static func apply(_ overlay:CamcorderDateOverlay,to image:CIImage,sourceTime:RationalTime)->CIImage {
        apply(overlay,to:image,sourceSeconds:sourceTime.seconds)
    }
    static func apply(_ overlay:CamcorderDateOverlay,to image:CIImage,sourceSeconds:Double)->CIImage {
        guard overlay.enabled,overlay.isValid else{return image}
        let extent=image.extent
        guard extent.width.isFinite,extent.height.isFinite,extent.width>0,extent.height>0 else{return image}
        let margin=min(extent.width,extent.height)*0.05
        let text=overlay.text(atSourceSeconds:sourceSeconds)
        // Fit the entire timestamp even on small canvases. Cache only its tight
        // bitmap, never a full-frame transparent surface per elapsed second.
        let initialFontSize=min(extent.width,extent.height)*0.038
        func line(_ size:CGFloat)->CTLine {
            let font=CTFontCreateWithName("Menlo-Bold" as CFString,size,nil)
            return CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font,NSAttributedString.Key(kCTForegroundColorAttributeName as String):CGColor(gray:1,alpha:1)]))
        }
        let initial=line(initialFontSize)
        let initialWidth=CGFloat(CTLineGetTypographicBounds(initial,nil,nil,nil))
        let fontSize=initialFontSize*min(1,(extent.width-2*margin)/max(1,initialWidth))
        let key="\(fontSize)|\(text)" as NSString
        let bitmap:CGImage
        if let cached=cache.images.object(forKey:key){bitmap=cached}
        else {
            let textLine=line(fontSize)
            var ascent:CGFloat=0,descent:CGFloat=0
            let textWidth=CGFloat(CTLineGetTypographicBounds(textLine,&ascent,&descent,nil))
            let padding=max(1,fontSize*0.12),w=Int(ceil(textWidth+padding*2)),h=Int(ceil(ascent+descent+padding*2))
            guard let context=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return image}
            context.textPosition=CGPoint(x:padding,y:padding+descent)
            context.setShadow(offset:CGSize(width:padding/2,height:-padding/2),blur:padding,color:CGColor(gray:0,alpha:1))
            CTLineDraw(textLine,context)
            guard let result=context.makeImage() else{return image}
            bitmap=result;cache.images.setObject(result,forKey:key,cost:w*h*4)
        }
        let right=overlay.corner == .topRight || overlay.corner == .bottomRight
        let top=overlay.corner == .topRight || overlay.corner == .topLeft
        let x=right ? extent.maxX-margin-CGFloat(bitmap.width):extent.minX+margin
        let y=top ? extent.maxY-margin-CGFloat(bitmap.height):extent.minY+margin
        return CIImage(cgImage:bitmap).transformed(by:CGAffineTransform(translationX:x,y:y)).composited(over:image)
    }
}
