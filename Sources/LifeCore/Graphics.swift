import Foundation

public struct GraphicPoint: Codable, Equatable, Sendable {
    public var x: Double; public var y: Double
    public init(x: Double, y: Double) { self.x=x; self.y=y }
    var isValid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}
public struct GraphicRect: Codable, Equatable, Sendable {
    public var x: Double; public var y: Double; public var width: Double; public var height: Double
    public init(x: Double = 0.25, y: Double = 0.25, width: Double = 0.5, height: Double = 0.5) { self.x=x; self.y=y; self.width=width; self.height=height }
    var isValid: Bool { [x,y,width,height].allSatisfy(\.isFinite) && [x,y,width,height].allSatisfy { (0...1).contains($0) } && x+width <= 1 && y+height <= 1 }
}
public enum ShapeKind: String, Codable, CaseIterable, Sendable { case rectangle, roundedRectangle, ellipse, line, arrow }
public struct ShapeContent: Codable, Equatable, Sendable {
    public var kind: ShapeKind; public var rect: GraphicRect; public var fill: RGBAColor; public var stroke: RGBAColor
    /// Stroke width and corner radius are fractions of the smaller canvas dimension.
    public var strokeWidth: Double; public var cornerRadius: Double
    public init(kind: ShapeKind, rect: GraphicRect = .init(), fill: RGBAColor = .white, stroke: RGBAColor = .black, strokeWidth: Double = 0.005, cornerRadius: Double = 0.04) { self.kind=kind; self.rect=rect; self.fill=fill; self.stroke=stroke; self.strokeWidth=strokeWidth; self.cornerRadius=cornerRadius }
    var isValid: Bool {
        rect.isValid && fill.isValid && stroke.isValid && strokeWidth.isFinite && (0...0.25).contains(strokeWidth) && cornerRadius.isFinite && (0...0.5).contains(cornerRadius) &&
        ((kind == .line || kind == .arrow) ? (rect.width > 0 || rect.height > 0) : (rect.width > 0 && rect.height > 0))
    }
}
public enum DrawingTool: String, Codable, CaseIterable, Sendable { case pen, highlighter }
public struct DrawingStroke: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID; public var points: [GraphicPoint]; public var color: RGBAColor; public var width: Double; public var tool: DrawingTool
    public init(id: UUID = UUID(), points: [GraphicPoint], color: RGBAColor = .white, width: Double = 0.006, tool: DrawingTool = .pen) { self.id=id; self.points=points; self.color=color; self.width=width; self.tool=tool }
    var isValid: Bool { !points.isEmpty && points.count <= 10000 && points.allSatisfy(\.isValid) && color.isValid && width.isFinite && (0.0001...0.25).contains(width) }
}
public struct DrawingContent: Codable, Equatable, Sendable {
    public var strokes: [DrawingStroke]
    public init(strokes: [DrawingStroke] = []) { self.strokes=strokes }
    var isValid: Bool { strokes.count <= 2000 && strokes.reduce(0) { $0+$1.points.count } <= 100000 && Set(strokes.map(\.id)).count == strokes.count && strokes.allSatisfy(\.isValid) }
}
/// All coordinates are normalized, with the origin at the canvas's upper-left corner.
public enum GraphicContent: Codable, Equatable, Sendable {
    case shape(ShapeContent)
    case drawing(DrawingContent)
    public var isValid: Bool {
        switch self { case .shape(let shape): shape.isValid; case .drawing(let drawing): drawing.isValid }
    }
}
