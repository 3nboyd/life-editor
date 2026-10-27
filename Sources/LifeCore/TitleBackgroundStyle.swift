import Foundation

public enum TitleBackgroundShape:String,Codable,CaseIterable,Sendable {
    case none,square,rounded,pill,speechBubble
    public var label:String {switch self{case .none:"None";case .square:"Square";case .rounded:"Rounded";case .pill:"Pill";case .speechBubble:"Bubble"}}
}
/// Canvas pixels, matching title font size and outline units. Positive shadow Y
/// moves downward. Nil on TitleStyle retains the pre-schema-6 bitmap exactly.
public struct TitleBackgroundStyle:Codable,Equatable,Sendable {
    public var shape:TitleBackgroundShape
    public var padding:Double
    public var cornerRadius:Double
    public var borderWidth:Double
    public var borderColor:RGBAColor
    public var shadowColor:RGBAColor
    public var shadowBlur:Double
    public var shadowOffsetX:Double
    public var shadowOffsetY:Double
    public init(shape:TitleBackgroundShape = .rounded,padding:Double = 12,cornerRadius:Double = 0.2,borderWidth:Double = 0,borderColor:RGBAColor = .white,shadowColor:RGBAColor = .clear,shadowBlur:Double = 0,shadowOffsetX:Double = 0,shadowOffsetY:Double = 0){self.shape=shape;self.padding=padding;self.cornerRadius=cornerRadius;self.borderWidth=borderWidth;self.borderColor=borderColor;self.shadowColor=shadowColor;self.shadowBlur=shadowBlur;self.shadowOffsetX=shadowOffsetX;self.shadowOffsetY=shadowOffsetY}
    public var isValid:Bool {
        [padding,cornerRadius,borderWidth,shadowBlur,shadowOffsetX,shadowOffsetY].allSatisfy(\.isFinite) && (0...512).contains(padding) && (0...1).contains(cornerRadius) && (0...100).contains(borderWidth) && (0...100).contains(shadowBlur) && (-512...512).contains(shadowOffsetX) && (-512...512).contains(shadowOffsetY) && borderColor.isValid && shadowColor.isValid
    }
}
