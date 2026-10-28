import SwiftUI
import LifeCore

struct DrawingControls:View {
    @ObservedObject var store:EditorStore
    private var editing:Bool{store.drawingMode==4}
    private var color:Binding<RGBAColor>{Binding(get:{editing ? store.selectedDrawingStroke?.color ?? store.drawingColor:store.drawingColor},set:{value in if editing{store.editDrawingStroke{$0.color=value}}else{store.drawingColor=value}})}
    private var width:Binding<Double>{Binding(get:{editing ? store.selectedDrawingStroke?.width ?? store.drawingWidth:store.drawingWidth},set:{value in if editing{store.editDrawingStroke{$0.width=value}}else{store.drawingWidth=value}})}
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            Picker("Drawing tool",selection:$store.drawingMode){
                Image(systemName:"pencil.tip").tag(1).help("Pen").accessibilityLabel("Pen")
                Image(systemName:"highlighter").tag(2).help("Highlighter").accessibilityLabel("Highlighter")
                Image(systemName:"eraser").tag(3).help("Erase stroke").accessibilityLabel("Erase stroke")
                Image(systemName:"cursorarrow").tag(4).help("Edit strokes").accessibilityLabel("Edit strokes")
            }.pickerStyle(.segmented)
            if editing {strokeSelection}
            Group{
                if store.drawingMode != 3 {
                    SharedColorPicker(label:"Color",color:color,store:store)
                    HStack{Text("Opacity");Slider(value:Binding(get:{color.wrappedValue.alpha},set:{color.wrappedValue.alpha=$0}),in:0...1,onEditingChanged:gesture).accessibilityLabel("Stroke opacity");Text(color.wrappedValue.alpha,format:.percent.precision(.fractionLength(0))).font(.caption.monospacedDigit()).frame(width:34)}
                }
                HStack{Text(store.drawingMode==3 ? "Radius":"Width");Slider(value:width,in:min(0.0001,width.wrappedValue)...max(0.05,width.wrappedValue),onEditingChanged:gesture).accessibilityLabel(store.drawingMode==3 ? "Eraser radius":"Stroke width");Text(width.wrappedValue*100,format:.number.precision(.fractionLength(1))).font(.caption.monospacedDigit()).frame(width:30)}
            }.disabled(editing && store.selectedDrawingStroke==nil)
            if editing,let stroke=store.selectedDrawingStroke {
                Picker("Stroke",selection:Binding(get:{stroke.tool},set:{tool in store.editDrawingStroke{$0.tool=tool}})){
                    Image(systemName:"pencil.tip").tag(DrawingTool.pen).accessibilityLabel("Pen")
                    Image(systemName:"highlighter").tag(DrawingTool.highlighter).accessibilityLabel("Highlighter")
                }.pickerStyle(.segmented)
                DisclosureGroup("Points") {
                    VStack(spacing:10){
                        Stepper("\(store.selectedDrawingPointIndex+1) / \(stroke.points.count)",value:$store.selectedDrawingPointIndex,in:0...max(0,stroke.points.count-1)).monospacedDigit().accessibilityLabel("Selected stroke point")
                        if stroke.points.indices.contains(store.selectedDrawingPointIndex){HStack{coordinate("X",x:true);coordinate("Y",x:false)}}
                    }.padding(.top,6)
                }
            }
            HStack{
                Button{store.editSelected{$0.graphic = .drawing(.init())};store.selectDrawingStroke(nil)}label:{Image(systemName:"trash.slash").frame(width:24,height:24)}.help("Clear drawing").accessibilityLabel("Clear drawing").disabled(store.selectedDrawing?.strokes.isEmpty ?? true)
                Spacer()
                Button{store.drawingMode=0;store.panel=nil}label:{Image(systemName:"checkmark").frame(width:24,height:24)}.help("Finish drawing").accessibilityLabel("Finish drawing")
            }
        }.onChange(of:store.drawingMode){if editing,store.selectedDrawingStroke==nil{store.selectDrawingStroke(store.selectedDrawing?.strokes.last?.id)}}

    }
    private func gesture(_ active:Bool){if editing{if active{store.beginGesture()}else{store.endGesture()}}}
    private var strokeSelection:some View {
        HStack(spacing:6){
            Picker("Stroke",selection:Binding(get:{store.selectedDrawingStrokeID},set:{store.selectDrawingStroke($0)})){
                Text("Select").tag(nil as UUID?)
                ForEach(Array((store.selectedDrawing?.strokes ?? []).enumerated()),id:\.element.id){index,stroke in Text("\(index+1)").tag(Optional(stroke.id))}
            }.labelsHidden().accessibilityLabel("Select drawing stroke")
            Button{store.duplicateDrawingStroke()}label:{Image(systemName:"plus.square.on.square").frame(width:24,height:24)}.help("Duplicate stroke").accessibilityLabel("Duplicate stroke").disabled(store.selectedDrawingStroke==nil)
            Button{store.deleteDrawingStroke()}label:{Image(systemName:"trash").frame(width:24,height:24)}.help("Delete stroke").accessibilityLabel("Delete stroke").disabled(store.selectedDrawingStroke==nil)
        }
    }
    private func coordinate(_ label:String,x:Bool)->some View {
        HStack(spacing:4){Text(label);TextField(label,value:Binding(get:{
            guard let stroke=store.selectedDrawingStroke,stroke.points.indices.contains(store.selectedDrawingPointIndex) else{return 0.0}
            let point=stroke.points[store.selectedDrawingPointIndex];return (x ? point.x:point.y)*100
        },set:{value in
            guard value.isFinite,(0...100).contains(value),let stroke=store.selectedDrawingStroke,stroke.points.indices.contains(store.selectedDrawingPointIndex) else{return}
            var point=stroke.points[store.selectedDrawingPointIndex];if x{point.x=value/100}else{point.y=value/100};store.moveDrawingPoint(point)
        }),format:.number.precision(.fractionLength(0...2))).textFieldStyle(.roundedBorder).accessibilityLabel("Point \(label) percent")}
    }
}
