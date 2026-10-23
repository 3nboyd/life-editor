import Foundation

public enum TextFamily:String,CaseIterable,Sendable {
    case plain="Plain",bold="Bold",condensed="Condensed",serif="Serif",handwritten="Handwritten",outlined="Outlined",neon="Neon",typewriter="Typewriter"
}
public enum TextPresetError:LocalizedError {
    case notTitle,duplicateBloom
    public var errorDescription:String?{switch self{case .notTitle:"Select a text clip.";case .duplicateBloom:"Use one Bloom adjustment before applying a text preset."}}
}
/// Original appearance presets. The Typewriter family changes typography only;
/// the separate entrance animation, content, timing and font size remain editable.
/// Presets own font/fill/background/outline and the canonical Bloom value. Other
/// families reset Bloom to zero in place; unrelated effects and instance metadata
/// survive. Multiple Bloom instances require explicit user cleanup first.
public enum TextPresets {
    public static let bloomID="life.adjust.bloom"
    public static func applying(_ family:TextFamily,to original:Clip)throws->Clip {
        guard var title=original.title else{throw TextPresetError.notTitle}
        var effects=original.effects ?? []
        let bloom=effects.indices.filter{effects[$0].stableID==bloomID}
        guard bloom.count<=1 else{throw TextPresetError.duplicateBloom}
        var clip=original,style=title.style ?? .init()
        style.color = .white;style.background = .clear;style.outlineWidth=0;style.outlineColor = .black
        switch family {
        case .plain:style.fontName="HelveticaNeue"
        case .bold:style.fontName="Helvetica-Bold"
        case .condensed:style.fontName="HelveticaNeue-CondensedBold"
        case .serif:style.fontName="Georgia"
        case .handwritten:style.fontName="Noteworthy"
        case .outlined:style.fontName="Helvetica-Bold";style.outlineWidth=2
        case .neon:style.fontName="HelveticaNeue-Light";style.color = .init(red:0.2,green:1,blue:0.8);style.outlineWidth=0.6;style.outlineColor = .white
        case .typewriter:style.fontName="Menlo"
        }
        if let index=bloom.first {
            effects[index].parameters["value"]=family == .neon ? 0.8:0
            if family == .neon {effects[index].strength=1;effects[index].isEnabled=true}
            clip.effects=effects
        }else if family == .neon {
            var effect=NativeEffectRegistry.make(bloomID);effect.parameters["value"]=0.8;effects.append(effect);clip.effects=effects
        }
        title.style=style;clip.title=title;return clip
    }
}
