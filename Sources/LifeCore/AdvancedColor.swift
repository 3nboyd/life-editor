import Foundation

/// Original SDR controls. Curves use five ordered knots at 0, ¼, ½, ¾ and 1.
/// Piecewise linear interpolation avoids overshoot and preserves exact neutral values.
public enum AdvancedColor {
    public static let curveChannels=["master","red","green","blue"]
    public static let hueBands=["red","yellow","green","cyan","blue","magenta"]
    public static func isValid(_ effect:EffectInstance)->Bool {
        if effect.stableID == "life.adjust.levels" {
            return (effect.parameters["black"] ?? 0) < (effect.parameters["white"] ?? 1)
        }
        return true
    }
    public static func curve(_ effect:EffectInstance,channel:String)->[Double] {
        (0...4).map { effect.parameters["\(channel)\($0)"] ?? Double($0)/4 }
    }
    public static func evaluateCurve(_ input:Double,values:[Double])->Double {
        guard values.count==5 else{return input}
        let x=max(0,min(1,input))*4,index=min(3,Int(x)),fraction=x-Double(index)
        return values[index]+(values[index+1]-values[index])*fraction
    }
}
