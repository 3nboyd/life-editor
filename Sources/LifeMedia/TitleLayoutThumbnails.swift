import Foundation
import CoreImage
import LifeCore

public actor TitleLayoutThumbnails {
    public static let shared=TitleLayoutThumbnails()
    private let context=CIContext()
    public func image(for preset:TitleLayoutPreset)throws->CGImage {
        try Task.checkCancellation()
        let clip=try preset.applying(to:Clip(duration:.init(value:1,timescale:1),title:.init(text:preset.rawValue)),canvasHeight:720)
        guard var title=clip.title else{throw MediaError.exportUnavailable}
        title.fontSize /= 4
        let size=CGSize(width:320,height:180)
        guard let image=TitleRenderer.image(title,size:size),let output=context.createCGImage(image,from:CGRect(origin:.zero,size:size),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)) else{throw MediaError.exportUnavailable}
        return output
    }
}
