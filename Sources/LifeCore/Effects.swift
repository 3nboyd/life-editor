import Foundation

public struct EffectParameterDefinition: Equatable, Sendable {
    public let name: String
    public let defaultValue: Double
    public let range: ClosedRange<Double>
    public let supportsAnimation: Bool
    public init(name: String, defaultValue: Double, range: ClosedRange<Double>, supportsAnimation: Bool = true) { self.name=name; self.defaultValue=defaultValue; self.range=range; self.supportsAnimation=supportsAnimation }
}
public struct EffectDefinition: Identifiable, Equatable, Sendable {
    public var id: String { stableID }
    public let stableID: String
    public let name: String
    public let parameters: [EffectParameterDefinition]
    public let supportsAnimation: Bool
    public let isTimeVarying: Bool
    public init(stableID: String, name: String, parameters: [EffectParameterDefinition] = [], supportsAnimation: Bool = true, isTimeVarying: Bool = false) { self.stableID=stableID; self.name=name; self.parameters=parameters; self.supportsAnimation=supportsAnimation; self.isTimeVarying=isTimeVarying }
}
public struct EffectInstance: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var stableID: String
    public var parameters: [String:Double]
    public var strength: Double
    public var seed: UInt64
    public var isEnabled: Bool
    public init(id: UUID = UUID(), stableID: String, parameters: [String:Double] = [:], strength: Double = 1, seed: UInt64 = 0, isEnabled: Bool = true) { self.id=id; self.stableID=stableID; self.parameters=parameters; self.strength=strength; self.seed=seed; self.isEnabled=isEnabled }
}
/// Stable original look identifiers. Rendering owns each definition's implementation.
public enum NativeEffectRegistry {
    public static let definitions: [EffectDefinition] = [
        ("grayscale","Grayscale"),("highContrast","High Contrast"),("LA","LA"),("desert","Desert"),
        ("clean","Clean"),("vivid","Vivid"),("softPortrait","Soft Portrait"),("cool","Cool"),
        ("cinematic","Cinematic"),("goldenHour","Golden Hour"),("fadedFilm","Faded Film"),("Y2K","Y2K"),
        ("VHS","VHS"),("disposable","Disposable"),("neon","Neon"),("mutedPastel","Muted Pastel")
    ].map { key,name in
        EffectDefinition(stableID:"life.filter."+key,name:name,
            parameters:(key == "VHS" || key == "disposable" || key == "fadedFilm") ? [.init(name:"grain",defaultValue:0.2,range:0...1)] : [],
            isTimeVarying:key == "VHS")
    }
    public static let adjustments: [EffectDefinition] = [
        ("exposure","Exposure",-4.0,4.0,0.0),("brightness","Brightness",-1,1,0),("contrast","Contrast",0,2,1),
        ("highlights","Highlights",0,2,1),("shadows","Shadows",-1,1,0),("saturation","Saturation",0,2,1),
        ("vibrance","Vibrance",-1,1,0),("temperature","Temperature",-2000,2000,0),("tint","Tint",-100,100,0),
        ("hue","Hue",-180,180,0),("bloom","Bloom",0,1,0),("sharpen","Sharpen",0,2,0),
        ("clarity","Clarity",0,2,0),("noiseReduction","Noise Reduction",0,1,0),("vignette","Vignette",0,2,0),("grain","Grain",0,1,0)
    ].map { key,name,lower,upper,initial in EffectDefinition(stableID:"life.adjust."+key,name:name,parameters:[.init(name:"value",defaultValue:initial,range:lower...upper)]) }
    public static func definition(for stableID: String) -> EffectDefinition? { (definitions+adjustments).first { $0.stableID == stableID } }
    public static func make(_ stableID: String, strength: Double = 1, seed: UInt64 = 0) -> EffectInstance {
        EffectInstance(stableID:stableID,parameters:Dictionary(uniqueKeysWithValues:(definition(for:stableID)?.parameters ?? []).map { ($0.name,$0.defaultValue) }),strength:strength,seed:seed)
    }
}
public struct RGBAColor: Codable, Equatable, Sendable {
    public var red: Double; public var green: Double; public var blue: Double; public var alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) { self.red=red; self.green=green; self.blue=blue; self.alpha=alpha }
    public static let white=Self(red:1,green:1,blue:1)
    public static let black=Self(red:0,green:0,blue:0)
    public static let clear=Self(red:0,green:0,blue:0,alpha:0)
    var isValid: Bool { [red,green,blue,alpha].allSatisfy { $0.isFinite && (0...1).contains($0) } }
}
/// Canvas-relative center/crop, dimensionless scale, rotation in degrees.
public struct VisualTransform: Codable, Equatable, Sendable {
    public var x: Double; public var y: Double; public var scaleX: Double; public var scaleY: Double; public var rotationDegrees: Double
    public var cropLeft: Double; public var cropRight: Double; public var cropTop: Double; public var cropBottom: Double
    public var flipHorizontal: Bool; public var flipVertical: Bool
    public init(x: Double = 0.5, y: Double = 0.5, scaleX: Double = 1, scaleY: Double = 1, rotationDegrees: Double = 0, cropLeft: Double = 0, cropRight: Double = 0, cropTop: Double = 0, cropBottom: Double = 0, flipHorizontal: Bool = false, flipVertical: Bool = false) { self.x=x; self.y=y; self.scaleX=scaleX; self.scaleY=scaleY; self.rotationDegrees=rotationDegrees; self.cropLeft=cropLeft; self.cropRight=cropRight; self.cropTop=cropTop; self.cropBottom=cropBottom; self.flipHorizontal=flipHorizontal; self.flipVertical=flipVertical }
    var isValid: Bool {
        [x,y,scaleX,scaleY,rotationDegrees,cropLeft,cropRight,cropTop,cropBottom].allSatisfy(\.isFinite) && (-10...10).contains(x) && (-10...10).contains(y) && (0.001...100).contains(scaleX) && (0.001...100).contains(scaleY) && abs(rotationDegrees) <= 36000 && [cropLeft,cropRight,cropTop,cropBottom].allSatisfy { (0...1).contains($0) } && cropLeft+cropRight < 1 && cropTop+cropBottom < 1
    }
}
public struct TitleStyle: Codable, Equatable, Sendable {
    public var fontName: String?; public var x: Double; public var y: Double
    public var color: RGBAColor; public var background: RGBAColor
    public var cornerRadius: Double; public var outlineWidth: Double; public var outlineColor: RGBAColor
    public init(fontName: String? = nil, x: Double = 0.5, y: Double = 0.82, color: RGBAColor = .white, background: RGBAColor = .clear, cornerRadius: Double = 0, outlineWidth: Double = 0, outlineColor: RGBAColor = .black) { self.fontName=fontName; self.x=x; self.y=y; self.color=color; self.background=background; self.cornerRadius=cornerRadius; self.outlineWidth=outlineWidth; self.outlineColor=outlineColor }
    var isValid: Bool { [x,y,cornerRadius,outlineWidth].allSatisfy(\.isFinite) && (0...1).contains(x) && (0...1).contains(y) && (0...1).contains(cornerRadius) && (0...100).contains(outlineWidth) && color.isValid && background.isValid && outlineColor.isValid }
}
