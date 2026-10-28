import Foundation

/// Reusable canvas-relative placement recipes. Applying a recipe changes only
/// size and position; words, appearance, animation, timing and effects survive.
public enum TitleLayoutPreset:String,CaseIterable,Sendable {
    case title="Title",lowerThird="Lower Third",label="Label",lyrics="Lyrics"
    public func applying(to original:Clip,canvasHeight:Int)throws->Clip {
        guard var title=original.title else{throw TextPresetError.notTitle}
        guard (1...16384).contains(canvasHeight) else{throw DocumentError.invalidTiming}
        var clip=original,style=title.style ?? .init()
        style.x=0.5
        switch self {
        case .title:style.y=0.5;title.fontSize=Double(canvasHeight)*0.085
        case .lowerThird:style.y=0.82;title.fontSize=Double(canvasHeight)*0.05
        case .label:style.y=0.16;title.fontSize=Double(canvasHeight)*0.04
        case .lyrics:style.y=0.7;title.fontSize=Double(canvasHeight)*0.065
        }
        title.fontSize=max(1,title.fontSize)
        title.style=style;clip.title=title;return clip
    }
}
