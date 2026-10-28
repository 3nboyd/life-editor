import CoreImage
import LifeCore

public actor CaptionThumbnails {
    public static let shared=CaptionThumbnails()
    private let context=CIContext()
    public func image(for preset:CaptionPreset)throws->CGImage {
        try Task.checkCancellation()
        let clip=try preset.applying(to:.init(duration:.init(value:1,timescale:1),title:.init(text:"Your words")),canvasHeight:360)
        guard var title=clip.title else{throw MediaError.exportUnavailable}
        let scale=22/title.fontSize;title.fontSize=22
        title.style?.x=0.5;title.style?.y=0.5;title.style?.outlineWidth *= scale
        if var background=title.style?.backgroundStyle {
            background.padding *= scale;background.borderWidth *= scale;background.shadowBlur *= scale
            background.shadowOffsetX *= scale;background.shadowOffsetY *= scale
            title.style?.backgroundStyle=background
        }
        title.style?.typography?.lineSpacing *= scale
        let size=CGSize(width:240,height:90)
        guard let image=TitleRenderer.image(title,size:size),let result=context.createCGImage(image,from:CGRect(origin:.zero,size:size),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)) else{throw MediaError.exportUnavailable}
        return result
    }
}
