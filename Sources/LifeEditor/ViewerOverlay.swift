import SwiftUI
import LifeCore

struct ViewerOverlay:View {
    @ObservedObject var store:EditorStore
    @State private var original:VisualTransform?
    @State private var editingText=false
    @State private var stroke:[GraphicPoint]=[]
    var body:some View {
        GeometryReader { geometry in
            let project=store.document.sequence.settings
            let scale=min(geometry.size.width/Double(project.width),geometry.size.height/Double(project.height))
            let canvas=CGSize(width:Double(project.width)*scale,height:Double(project.height)*scale)
            let origin=CGPoint(x:(geometry.size.width-canvas.width)/2,y:(geometry.size.height-canvas.height)/2)
            ZStack {
                Color.clear.contentShape(Rectangle()).onTapGesture {
                    let active=Array(TimelineEvaluator.evaluate(.init(document:store.document),at:store.time(store.playhead)).reversed().filter{ evaluated in store.document.sequence.tracks.first(where:{$0.id==evaluated.trackID}).map{!$0.isHidden && $0.kind != .audio} ?? false })
                    if NSEvent.modifierFlags.contains(.shift),let current=active.firstIndex(where:{$0.clip.id==store.selection}),current+1<active.count {store.selection=active[current+1].clip.id}
                    else {store.selection=active.first?.clip.id}
                }
                if !store.samplingColor,store.drawingMode==0,let clip=store.selectedClip,store.document.sequence.tracks.first(where:{$0.clips.contains(where:{$0.id==clip.id})})?.kind != .audio,clip.start.seconds<=store.playhead,store.playhead<clip.end.seconds {
                    let visual=clip.visual ?? VisualTransform()
                    let isTitle=clip.title != nil
                    let position=CGPoint(x:origin.x+canvas.width*(visual.x+(isTitle ? (clip.title?.style?.x ?? 0.5)-0.5:0)),y:origin.y+canvas.height*(visual.y+(isTitle ? (clip.title?.style?.y ?? 0.82)-0.5:0)))
                    let box=CGSize(width:canvas.width*(isTitle ? 0.6:1)*visual.scaleX,height:canvas.height*(isTitle ? 0.16:1)*visual.scaleY)
                    Rectangle().stroke(.white.opacity(0.7),style:StrokeStyle(lineWidth:1,dash:[4,3])).frame(width:box.width,height:box.height).position(position)
                        .contentShape(Rectangle())
                        .gesture(DragGesture().onChanged{value in
                            if original==nil {original=visual;store.beginGesture()}
                            guard let baseline=original else{return}
                            store.editSelected {clip in var updated=baseline;updated.x+=value.translation.width/canvas.width;updated.y+=value.translation.height/canvas.height;clip.visual=updated}
                        }.onEnded{_ in original=nil;store.endGesture()})
                        .onTapGesture(count:2){if isTitle{editingText=true;store.panel = .title}}
                        .accessibilityLabel("Selected object. Position and size are also available in Clip controls.")
                    ForEach(0..<4,id:\.self){index in
                        Rectangle().fill(.white).frame(width:8,height:8)
                            .position(x:position.x+(index%2==0 ? -box.width/2:box.width/2),y:position.y+(index<2 ? -box.height/2:box.height/2))
                            .gesture(DragGesture().onChanged{value in
                                if original==nil{original=visual;store.beginGesture()}
                                guard let baseline=original else{return}
                                let amount=1+(value.translation.width*(index%2==0 ? -1:1))/max(1,box.width)
                                store.editSelected{clip in var updated=baseline;updated.scaleX=max(0.01,min(10,baseline.scaleX*amount));updated.scaleY=max(0.01,min(10,baseline.scaleY*amount));clip.visual=updated}
                            }.onEnded{_ in original=nil;store.endGesture()})
                            .accessibilityHidden(true)
                    }
                    if editingText,isTitle {
                        TextField("Text",text:Binding(get:{store.selectedClip?.title?.text ?? ""},set:{v in store.editSelected{$0.title?.text=v}}),axis:.vertical).textFieldStyle(.roundedBorder).frame(width:min(400,box.width)).position(position).onSubmit{editingText=false}
                    }
                }
                if !store.samplingColor,(1...3).contains(store.drawingMode) {
                    Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged{value in
                        let raw:GraphicPoint
                        if let clip=store.selectedClip,store.selectedDrawing != nil,clip.start.seconds<=store.playhead,store.playhead<clip.end.seconds {
                            raw=DrawingPointOverlay(store:store,canvas:canvas,origin:origin).source(value.location)
                        }else{raw = .init(x:(value.location.x-origin.x)/canvas.width,y:(value.location.y-origin.y)/canvas.height)}
                        let point=GraphicPoint(x:max(0,min(1,raw.x)),y:max(0,min(1,raw.y)))
                        if stroke.count<10000,stroke.last.map({hypot($0.x-point.x,$0.y-point.y)>0.001}) ?? true {stroke.append(point)}
                    }.onEnded{_ in store.commitDrawing(stroke);stroke=[]})
                    let visual:VisualTransform = {
                        if let clip=store.selectedClip,store.selectedDrawing != nil,clip.start.seconds<=store.playhead,store.playhead<clip.end.seconds{return clip.visual ?? .init()}
                        return .init()
                    }()
                    let width=store.drawingWidth*(store.drawingMode==3 ? 2:1)
                    let crop=CGRect(x:visual.cropLeft*canvas.width,y:visual.cropTop*canvas.height,width:(1-visual.cropLeft-visual.cropRight)*canvas.width,height:(1-visual.cropTop-visual.cropBottom)*canvas.height)
                    DrawingPreviewGeometry.outline(stroke,width:width,canvas:canvas)
                        .fill(store.drawingMode==3 ? Color.white.opacity(0.6):Color(.sRGB,red:store.drawingColor.red,green:store.drawingColor.green,blue:store.drawingColor.blue,opacity:store.drawingColor.alpha*(store.drawingMode==2 ? 0.35:1)))
                        .clipShape(Path(crop))
                        .transformEffect(DrawingPreviewGeometry.transform(visual,canvas:canvas,origin:origin))
                        .allowsHitTesting(false)

                }
                if !store.samplingColor,store.drawingMode==4 {
                    DrawingPointOverlay(store:store,canvas:canvas,origin:origin)
                }
                if store.samplingColor{
                    Color.clear.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded{value in
                        let x=(value.location.x-origin.x)/canvas.width,y=(value.location.y-origin.y)/canvas.height
                        guard (0...1).contains(x),(0...1).contains(y) else{return}
                        store.sampleViewerColor(x:x,y:y)
                    }).accessibilityLabel("Sample a viewer color")
                    VStack{HStack{Label("Sample color",systemImage:"eyedropper").font(.caption);Spacer();Button{store.cancelColorSampling()}label:{Image(systemName:"xmark")}.help("Cancel color sampling · Esc").accessibilityLabel("Cancel color sampling")};Spacer()}.padding(12)
                }
            }
        }.onExitCommand{if store.placementProposal != nil{store.cancelPlacement()}else{store.cancelColorSampling()}}.allowsHitTesting(store.panel != .multicam || store.samplingColor)
    }
}
