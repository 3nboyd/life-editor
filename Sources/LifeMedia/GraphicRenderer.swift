import Foundation
import CoreGraphics
import CoreImage
import LifeCore

public enum GraphicRenderer {
    /// Transparent premultiplied sRGB bitmap. The shared compositor performs working-space conversion.
    public static func image(_ graphic: GraphicContent, size: CGSize) -> CIImage? {
        guard graphic.isValid, size.width.isFinite, size.height.isFinite,
              size.width >= 1, size.height >= 1, size.width <= 16384, size.height <= 16384,
              size.width*size.height <= 33_554_432 else { return nil }
        let width=Int(size.width.rounded()), height=Int(size.height.rounded())
        guard let space=CGColorSpace(name:CGColorSpace.sRGB),
              let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        context.translateBy(x:0,y:CGFloat(height)); context.scaleBy(x:1,y:-1)
        context.setLineCap(.round); context.setLineJoin(.round)
        let canvas=CGSize(width:width,height:height), unit=min(canvas.width,canvas.height)
        switch graphic {
        case .shape(let shape):
            let r=shape.rect, rect=CGRect(x:r.x*canvas.width,y:r.y*canvas.height,width:r.width*canvas.width,height:r.height*canvas.height)
            let path=CGMutablePath()
            switch shape.kind {
            case .rectangle: path.addRect(rect)
            case .roundedRectangle:
                let radius=min(CGFloat(shape.cornerRadius)*unit,min(rect.width,rect.height)/2)
                path.addRoundedRect(in:rect,cornerWidth:radius,cornerHeight:radius)
            case .ellipse: path.addEllipse(in:rect)
            case .line, .arrow:
                let start=CGPoint(x:rect.minX,y:rect.minY), end=CGPoint(x:rect.maxX,y:rect.maxY)
                path.move(to:start); path.addLine(to:end)
                if shape.kind == .arrow {
                    let angle=atan2(end.y-start.y,end.x-start.x), length=min(hypot(rect.width,rect.height)*0.3,max(unit*0.025,CGFloat(shape.strokeWidth)*unit*4))
                    for sign: CGFloat in [-1,1] {
                        path.move(to:end)
                        path.addLine(to:CGPoint(x:end.x-length*cos(angle+sign*CGFloat.pi/6),y:end.y-length*sin(angle+sign*CGFloat.pi/6)))
                    }
                }
            }
            context.setFillColor(color(shape.fill)); context.setStrokeColor(color(shape.stroke)); context.setLineWidth(CGFloat(shape.strokeWidth)*unit)
            context.addPath(path)
            if shape.kind == .line || shape.kind == .arrow {
                if shape.strokeWidth > 0 { context.strokePath() }
            } else if shape.strokeWidth > 0 { context.drawPath(using:.fillStroke) }
            else { context.fillPath() }
        case .drawing(let drawing):
            for stroke in drawing.strokes {
                guard let first=stroke.points.first else { continue }
                let alpha=stroke.tool == .highlighter ? 0.35 : 1.0
                context.setStrokeColor(color(stroke.color,alpha:alpha)); context.setFillColor(color(stroke.color,alpha:alpha))
                let width=CGFloat(stroke.width)*unit
                context.setLineWidth(width)
                if stroke.points.count == 1 {
                    context.fillEllipse(in:CGRect(x:first.x*canvas.width-width/2,y:first.y*canvas.height-width/2,width:width,height:width))
                } else {
                    context.beginPath(); context.move(to:CGPoint(x:first.x*canvas.width,y:first.y*canvas.height))
                    for point in stroke.points.dropFirst() { context.addLine(to:CGPoint(x:point.x*canvas.width,y:point.y*canvas.height)) }
                    context.strokePath()
                }
            }
        }
        guard let image=context.makeImage() else { return nil }
        return CIImage(cgImage:image)
    }
    private static func color(_ color: RGBAColor, alpha: Double = 1) -> CGColor { CGColor(red:color.red,green:color.green,blue:color.blue,alpha:color.alpha*alpha) }
}
