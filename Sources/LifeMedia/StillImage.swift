import Foundation
import ImageIO
import CoreImage

/// Header-only probing and bounded, orientation-aware thumbnail decoding.
enum StillImage {
    static func dimensions(_ url:URL)->(width:Int,height:Int)?{
        guard let source=CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],let width=(properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,let height=(properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,width>0,height>0 else{return nil}
        let orientation=(properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation) ? (height,width):(width,height)
    }
    static func thumbnail(_ url:URL)->CIImage?{
        guard let source=CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:320,kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else{return nil}
        let scale=min(1,min(320/Double(image.width),180/Double(image.height)))
        return CIImage(cgImage:image).transformed(by:CGAffineTransform(scaleX:scale,y:scale))
    }
    static func original(_ url:URL)->CIImage?{CIImage(contentsOf:url,options:[.applyOrientationProperty:true])}
}
