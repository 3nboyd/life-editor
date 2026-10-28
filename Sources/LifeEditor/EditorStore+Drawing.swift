import Foundation
import LifeCore

extension EditorStore {
    var selectedDrawing:DrawingContent? {
        guard case .drawing(let drawing)=selectedClip?.graphic else{return nil}
        return drawing
    }
    var selectedDrawingStroke:DrawingStroke? { selectedDrawing?.strokes.first{$0.id==selectedDrawingStrokeID} }
    func selectDrawingStroke(_ id:UUID?) { selectedDrawingStrokeID=id;selectedDrawingPointIndex=0 }
    func editDrawingStroke(_ update:(inout DrawingStroke)->Void) {
        guard let id=selectedDrawingStroke?.id else{return}
        editSelected{clip in
            guard case .drawing(var drawing)=clip.graphic,let index=drawing.strokes.firstIndex(where:{$0.id==id}) else{return}
            update(&drawing.strokes[index]);clip.graphic = .drawing(drawing)
        }
    }
    func moveDrawingPoint(_ point:GraphicPoint,index:Int?=nil) {
        guard point.x.isFinite,point.y.isFinite else{return}
        let index=index ?? selectedDrawingPointIndex
        editDrawingStroke{stroke in
            guard stroke.points.indices.contains(index) else{return}
            stroke.points[index] = .init(x:max(0,min(1,point.x)),y:max(0,min(1,point.y)))
        }
    }
    func deleteDrawingStroke() {
        guard let id=selectedDrawingStroke?.id else{return}
        editSelected{clip in guard case .drawing(var drawing)=clip.graphic else{return};drawing.strokes.removeAll{$0.id==id};clip.graphic = .drawing(drawing)}
        if selectedDrawing?.strokes.contains(where:{$0.id==id}) == false {selectDrawingStroke(selectedDrawing?.strokes.last?.id)}
    }
    func duplicateDrawingStroke() {
        guard var stroke=selectedDrawingStroke else{return}
        stroke.id=UUID()
        // Preserve the shape near canvas boundaries rather than clamping each point.
        let dx=min(0.02,1-(stroke.points.map(\.x).max() ?? 1)),dy=min(0.02,1-(stroke.points.map(\.y).max() ?? 1))
        stroke.points=stroke.points.map{.init(x:$0.x+dx,y:$0.y+dy)}
        editSelected{clip in guard case .drawing(var drawing)=clip.graphic else{return};drawing.strokes.append(stroke);clip.graphic = .drawing(drawing)}
        if selectedDrawing?.strokes.contains(where:{$0.id==stroke.id}) == true {selectDrawingStroke(stroke.id)}
    }
    func commitDrawing(_ points:[GraphicPoint]) {
        guard (1...3).contains(drawingMode),!points.isEmpty else{return}
        let points=Array(points.prefix(10000)).filter{$0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)}
        guard !points.isEmpty else{return}
        if drawingMode==3 {
            // Erase whole strokes, including a segment crossing between sparse points.
            editSelected{clip in
                guard case .drawing(var drawing)=clip.graphic else{return}
                let canvas=document.sequence.settings
                let unit=Double(min(canvas.width,canvas.height))
                let eraser=DrawingEraser(points:points,width:Double(canvas.width),height:Double(canvas.height),
                                         maximumRadius:(drawingWidth+(drawing.strokes.map(\.width).max() ?? 0)/2)*unit)
                drawing.strokes.removeAll{stroke in eraser.intersects(stroke,radius:(drawingWidth+stroke.width/2)*unit)}
                clip.graphic = .drawing(drawing)
            }
            if selectedDrawingStroke==nil{selectDrawingStroke(nil)}
        }else{
            let stroke=DrawingStroke(points:points,color:drawingColor,width:drawingWidth,tool:drawingMode==2 ? .highlighter:.pen)
            if let clip=selectedClip,case .drawing=clip.graphic,clip.start.seconds<=playhead,playhead<clip.end.seconds {
                editSelected{clip in guard case .drawing(var drawing)=clip.graphic else{return};drawing.strokes.append(stroke);clip.graphic = .drawing(drawing)}
            }else{
                var next=document
                let clip=Clip(name:"Drawing",start:time(playhead),duration:.init(value:3,timescale:1),graphic:.drawing(.init(strokes:[stroke])))
                next.sequence.tracks.append(Track(name:"Drawing",kind:.drawing,clips:[clip]));replace(next)
                if document==next{selection=clip.id}
            }
            if selectedDrawing?.strokes.contains(where:{$0.id==stroke.id}) == true{selectDrawingStroke(stroke.id)}
        }
    }
    nonisolated static func drawingDistance(_ p:GraphicPoint,_ a:GraphicPoint,_ b:GraphicPoint)->Double {
        let dx=b.x-a.x,dy=b.y-a.y,length=dx*dx+dy*dy
        let t=length>0 ? max(0,min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/length)):0
        return hypot(p.x-a.x-t*dx,p.y-a.y-t*dy)
    }
}

/// A bounded spatial index over the actual swept eraser segments. Both the
/// narrow-phase distance and grid use square canvas pixels, never normalized XY.
private struct DrawingEraser {
    let width:Double
    let height:Double
    let cellSize:Double
    let resolution:Int
    let segments:[(GraphicPoint,GraphicPoint)]
    var cells:[Int:[Int]]=[:]
    init(points:[GraphicPoint],width:Double,height:Double,maximumRadius:Double) {
        self.width=width;self.height=height
        cellSize=max(max(width,height)/64,maximumRadius,1)
        resolution=Int(ceil(max(width,height)/cellSize))+2
        let metric=points.map{GraphicPoint(x:$0.x*width,y:$0.y*height)}
        segments=metric.count==1 ? [(metric[0],metric[0])]:Array(zip(metric,metric.dropFirst()))
        for (index,segment) in segments.enumerated(){
            for key in keys(segment.0,segment.1){cells[key,default:[]].append(index)}
        }
    }
    func intersects(_ stroke:DrawingStroke,radius:Double)->Bool {
        let points=stroke.points.map{GraphicPoint(x:$0.x*width,y:$0.y*height)}
        let strokeSegments=points.count==1 ? [(points[0],points[0])]:Array(zip(points,points.dropFirst()))
        for (a,b) in strokeSegments {
            var candidates=Set<Int>()
            for key in keys(a,b){
                let x=key%resolution,y=key/resolution
                for dy in -1...1 {for dx in -1...1 {
                    guard (0..<resolution).contains(x+dx),(0..<resolution).contains(y+dy),let values=cells[x+dx+resolution*(y+dy)] else{continue}
                    for index in values where candidates.insert(index).inserted {
                        let segment=segments[index]
                        if Self.distance(a,b,segment.0,segment.1)<=radius{return true}
                    }
                }}
            }
        }
        return false
    }
    /// Grid traversal is bounded by 128 crossed cells per segment. It only finds
    /// candidates; intersections use the original segment geometry without resampling.
    private func keys(_ a:GraphicPoint,_ b:GraphicPoint)->[Int] {
        var x=Int(floor(a.x/cellSize)),y=Int(floor(a.y/cellSize))
        let endX=Int(floor(b.x/cellSize)),endY=Int(floor(b.y/cellSize)),dx=b.x-a.x,dy=b.y-a.y
        let stepX=dx<0 ? -1:1,stepY=dy<0 ? -1:1
        var tx=dx==0 ? Double.infinity:((Double(x+(stepX>0 ? 1:0))*cellSize)-a.x)/dx
        var ty=dy==0 ? Double.infinity:((Double(y+(stepY>0 ? 1:0))*cellSize)-a.y)/dy
        let deltaX=dx==0 ? Double.infinity:cellSize/abs(dx),deltaY=dy==0 ? Double.infinity:cellSize/abs(dy)
        var result=[Int]()
        for _ in 0...(abs(endX-x)+abs(endY-y)+2) {
            result.append(x+resolution*y)
            if x==endX && y==endY{break}
            if tx<ty{x+=stepX;tx+=deltaX}
            else if ty<tx{y+=stepY;ty+=deltaY}
            else{x+=stepX;y+=stepY;tx+=deltaX;ty+=deltaY}
        }
        return result
    }
    private static func distance(_ a:GraphicPoint,_ b:GraphicPoint,_ c:GraphicPoint,_ d:GraphicPoint)->Double {
        let rx=b.x-a.x,ry=b.y-a.y,sx=d.x-c.x,sy=d.y-c.y,denominator=rx*sy-ry*sx
        if abs(denominator)>1e-12 {
            let t=((c.x-a.x)*sy-(c.y-a.y)*sx)/denominator
            let u=((c.x-a.x)*ry-(c.y-a.y)*rx)/denominator
            if (0...1).contains(t),(0...1).contains(u){return 0}
        }
        return min(EditorStore.drawingDistance(a,c,d),EditorStore.drawingDistance(b,c,d),
                   EditorStore.drawingDistance(c,a,b),EditorStore.drawingDistance(d,a,b))
    }
}
