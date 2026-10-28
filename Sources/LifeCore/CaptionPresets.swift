import Foundation

/// Original caption appearances, stored as ordinary editable title properties.
public enum CaptionPreset:String,CaseIterable,Sendable {
    case plain="Plain",box="Box",pill="Pill",lyric="Lyric"
    public func applying(to original:Clip,canvasHeight:Int)throws->Clip {
        guard var title=original.title else{throw TextPresetError.notTitle}
        guard (1...16384).contains(canvasHeight) else{throw DocumentError.invalidTiming}
        let size=max(1,Double(canvasHeight)*(self == .lyric ? 0.06:0.045))
        let shadow=TitleBackgroundStyle(shape:.none,padding:size*0.3,shadowColor:.init(red:0,green:0,blue:0,alpha:0.6),shadowBlur:min(100,size*0.12),shadowOffsetY:size*0.04)
        var style=TitleStyle(fontName:self == .lyric ? "Georgia":"Helvetica-Bold",x:0.5,y:self == .lyric ? 0.7:0.84,color:.white,background:.clear,outlineWidth:min(100,size*0.045),outlineColor:.black,backgroundStyle:shadow,typography:.init(alignment:.center,lineSpacing:size*0.1))
        switch self {
        case .plain:break
        case .box,.pill:
            style.background = .init(red:0.025,green:0.035,blue:0.04,alpha:0.84)
            style.backgroundStyle?.shape = self == .box ? .square:.pill
            style.outlineWidth=0
        case .lyric:style.outlineWidth=min(100,size*0.025)
        }
        title.fontSize=size;title.style=style
        var result=original;result.title=title;return result
    }
}
