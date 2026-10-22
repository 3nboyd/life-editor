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
                    let active=Array(TimelineEvaluator.evaluate(.init(document:store.document),at:store.time(store.playhead)).reversed().filter{ evaluated in store.document.sequence.tracks.first(where:{$0.id==evaluated.trackID})?.kind != .audio })
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
                if !store.samplingColor,store.drawingMode>0 {
                    Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged{value in
                        let point=GraphicPoint(x:max(0,min(1,(value.location.x-origin.x)/canvas.width)),y:max(0,min(1,(value.location.y-origin.y)/canvas.height)))
                        if stroke.count<10000,stroke.last.map({hypot($0.x-point.x,$0.y-point.y)>0.001}) ?? true {stroke.append(point)}
                    }.onEnded{_ in store.commitDrawing(stroke);stroke=[]})
                    Path{path in
                        for (index,point) in stroke.enumerated(){let p=CGPoint(x:origin.x+point.x*canvas.width,y:origin.y+point.y*canvas.height);if index==0{path.move(to:p)}else{path.addLine(to:p)}}
                    }.stroke(Color(.sRGB,red:store.drawingColor.red,green:store.drawingColor.green,blue:store.drawingColor.blue,opacity:store.drawingMode==2 ? 0.4:store.drawingColor.alpha),style:StrokeStyle(lineWidth:store.drawingWidth*min(canvas.width,canvas.height),lineCap:.round,lineJoin:.round)).allowsHitTesting(false)
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
