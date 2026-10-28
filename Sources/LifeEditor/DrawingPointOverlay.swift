import SwiftUI
import LifeCore

/// Geometry follows the same canvas-center scale, flip and rotation as the compositor.
struct DrawingPointOverlay:View {
    @ObservedObject var store:EditorStore
    let canvas:CGSize
    let origin:CGPoint
    @State private var dragging=false
    private var visual:VisualTransform{store.selectedClip?.visual ?? .init()}
    private var active:Bool{guard let clip=store.selectedClip else{return false};return clip.start.seconds<=store.playhead && store.playhead<clip.end.seconds}
    var body:some View {
        ZStack{
            if active {
                Color.clear.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded{value in select(at:value.location)})
                    .accessibilityHidden(true)
                if let stroke=store.selectedDrawingStroke {
                    Path{path in for (index,point) in stroke.points.enumerated(){if index==0{path.move(to:display(point))}else{path.addLine(to:display(point))}}}
                        .stroke(.white,style:.init(lineWidth:1,dash:[4,3])).allowsHitTesting(false)
                    if stroke.points.indices.contains(store.selectedDrawingPointIndex){
                        let point=stroke.points[store.selectedDrawingPointIndex]
                        Circle().fill(.black).overlay{Circle().stroke(.white,lineWidth:2)}.frame(width:12,height:12)
                            .padding(8).contentShape(Rectangle()).position(display(point))
                            .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("drawingCanvas")).onChanged{value in
                                if !dragging{dragging=true;store.beginGesture()}
                                store.moveDrawingPoint(source(value.location))
                            }.onEnded{_ in dragging=false;store.endGesture()})
                            .accessibilityLabel("Selected drawing point")
                            .accessibilityHint("Set X and Y in Drawing Points controls.")
                    }
                }
            }
        }.coordinateSpace(name:"drawingCanvas").onDisappear{if dragging{dragging=false;store.endGesture()}}
    }
    func display(_ point:GraphicPoint)->CGPoint {
        CGPoint(x:point.x*canvas.width,y:point.y*canvas.height).applying(DrawingPreviewGeometry.transform(visual,canvas:canvas,origin:origin))
    }
    func source(_ point:CGPoint)->GraphicPoint {
        let source=point.applying(DrawingPreviewGeometry.transform(visual,canvas:canvas,origin:origin).inverted())
        return .init(x:source.x/canvas.width,y:source.y/canvas.height)
    }
    func select(at point:CGPoint) {
        guard let strokes=store.selectedDrawing?.strokes else{return}
        for stroke in strokes.reversed(){
            let points=stroke.points.map(display),target=GraphicPoint(x:point.x,y:point.y)
            let distance:Double
            if points.count==1{distance=hypot(points[0].x-point.x,points[0].y-point.y)}else{
                distance=zip(points,points.dropFirst()).map{EditorStore.drawingDistance(target,.init(x:$0.0.x,y:$0.0.y),.init(x:$0.1.x,y:$0.1.y))}.min() ?? .infinity
            }
            if distance<=max(12,stroke.width*min(canvas.width,canvas.height)*max(visual.scaleX,visual.scaleY)/2){
                store.selectDrawingStroke(stroke.id)
                store.selectedDrawingPointIndex=points.indices.min{hypot(points[$0].x-point.x,points[$0].y-point.y)<hypot(points[$1].x-point.x,points[$1].y-point.y)} ?? 0
                return
            }
        }
        store.selectDrawingStroke(nil)
    }
}

/// Stroke in source canvas pixels before transforming the complete outline, so
/// nonuniform scale changes the pen footprint exactly as it changes saved media.
enum DrawingPreviewGeometry {
    static func outline(_ points:[GraphicPoint],width:Double,canvas:CGSize)->Path {
        let diameter=width*min(canvas.width,canvas.height)
        if points.count==1,let point=points.first{return Path(ellipseIn:.init(x:point.x*canvas.width-diameter/2,y:point.y*canvas.height-diameter/2,width:diameter,height:diameter))}
        var path=Path()
        for (index,point) in points.enumerated(){let position=CGPoint(x:point.x*canvas.width,y:point.y*canvas.height);if index==0{path.move(to:position)}else{path.addLine(to:position)}}
        return path.strokedPath(.init(lineWidth:diameter,lineCap:.round,lineJoin:.round))
    }
    static func transform(_ visual:VisualTransform,canvas:CGSize,origin:CGPoint)->CGAffineTransform {
        CGAffineTransform(translationX:-canvas.width/2,y:-canvas.height/2)
            .concatenating(.init(scaleX:visual.scaleX*(visual.flipHorizontal ? -1:1),y:visual.scaleY*(visual.flipVertical ? -1:1)))
            .concatenating(.init(rotationAngle:-visual.rotationDegrees * .pi/180))
            .concatenating(.init(translationX:origin.x+visual.x*canvas.width,y:origin.y+visual.y*canvas.height))
    }
}
