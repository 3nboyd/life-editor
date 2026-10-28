import SwiftUI
import LifeCore

struct AdvancedColorControls:View {
    @ObservedObject var store:EditorStore
    @State private var expanded=false
    @State private var section=0
    @State private var channel="master"
    @State private var band="red"
    @State private var point=2
    @State private var dragging=false
    init(store:EditorStore,expanded:Bool=false,section:Int=0){self.store=store;_expanded=State(initialValue:expanded);_section=State(initialValue:max(0,min(2,section)))}
    private var effectID:String{["life.adjust.curves","life.adjust.levels","life.adjust.hsl"][section]}
    var body:some View {
        DisclosureGroup(isExpanded:$expanded){
            VStack(spacing:12){
                Picker("Advanced adjustment",selection:$section){Text("Curves").tag(0);Text("Levels").tag(1);Text("HSL").tag(2)}.pickerStyle(.segmented).labelsHidden()
                if section==0 {
                    Picker("Curve channel",selection:$channel){Text("RGB").tag("master");Text("R").tag("red");Text("G").tag("green");Text("B").tag("blue")}.pickerStyle(.segmented).labelsHidden()
                    curveGraph
                    HStack {
                        Picker("Point",selection:$point){ForEach(0...4,id:\.self){Text("\($0*25)%").tag($0)}}.frame(maxWidth:.infinity)
                        TextField("Output",value:Binding(get:{value("life.adjust.curves",channel+String(point))},set:{setParameter("life.adjust.curves",channel+String(point),$0)}),format:.number.precision(.fractionLength(0...3))).textFieldStyle(.roundedBorder).frame(width:64).accessibilityLabel("Curve output at \(point*25) percent input")
                    }
                } else if section==1 {
                    control("Black",parameter:"black",range:0...0.99,id:"life.adjust.levels")
                    control("White",parameter:"white",range:0.01...1,id:"life.adjust.levels")
                    control("Gamma",parameter:"gamma",range:0.1...4,id:"life.adjust.levels")
                } else {
                    Picker("Color band",selection:$band){ForEach(AdvancedColor.hueBands,id:\.self){Text(String($0.prefix(1)).uppercased()).tag($0)}}.pickerStyle(.segmented).accessibilityLabel("HSL color band").labelsHidden()
                    Text(band.capitalized).font(.caption).foregroundStyle(.secondary)
                    control("Hue",parameter:band+"Hue",range:-60...60,id:"life.adjust.hsl")
                    control("Saturation",parameter:band+"Saturation",range:-1...1,id:"life.adjust.hsl")
                    control("Lightness",parameter:band+"Lightness",range:-1...1,id:"life.adjust.hsl")
                }
                HStack{Spacer();Button{reset(effectID)}label:{Image(systemName:"arrow.counterclockwise").frame(width:24,height:24)}.help("Reset \(["curves","levels","HSL"][section])").accessibilityLabel("Reset \(["curves","levels","HSL"][section])")}
            }.padding(.top,8)
        }label:{Label("Advanced",systemImage:"slider.horizontal.3")}
        .onDisappear{if dragging{store.endGesture();dragging=false}}
    }
    private var curveGraph:some View {
        GeometryReader{geometry in
            let width:CGFloat=max(1,geometry.size.width-24)
            let height:CGFloat=max(1,geometry.size.height-24)
            ZStack(alignment:.topLeading){
                RoundedRectangle(cornerRadius:5).fill(.black.opacity(0.25))
                gridPath(width:width,height:height).stroke(.white.opacity(0.12),lineWidth:1)
                curvePath(width:width,height:height).stroke(.primary,lineWidth:1.5)
                ForEach(0...4,id:\.self){index in curveHandle(index,width:width,height:height)}
            }.coordinateSpace(name:"curveGraph")
        }.frame(height:166).accessibilityLabel("RGB curve editor")
    }
    private func gridPath(width:CGFloat,height:CGFloat)->Path {
        Path{path in for index in 0...4 {
            let fraction=CGFloat(index)/4
            path.move(to:CGPoint(x:12+width*fraction,y:12));path.addLine(to:CGPoint(x:12+width*fraction,y:12+height))
            path.move(to:CGPoint(x:12,y:12+height*fraction));path.addLine(to:CGPoint(x:12+width,y:12+height*fraction))
        }}
    }
    private func curvePath(width:CGFloat,height:CGFloat)->Path {
        Path{path in for index in 0...4 {
            let output=value("life.adjust.curves",channel+String(index))
            let position=CGPoint(x:12+width*CGFloat(index)/4,y:12+height*CGFloat(1-output))
            if index==0{path.move(to:position)}else{path.addLine(to:position)}
        }}
    }
    private func curveHandle(_ index:Int,width:CGFloat,height:CGFloat)->some View {
        let output=value("life.adjust.curves",channel+String(index))
        return Circle().fill(index==point ? Color.accentColor:Color.primary).frame(width:12,height:12)
            .overlay(Circle().stroke(.black,lineWidth:index==point ? 2:0))
            .frame(width:24,height:24).contentShape(Rectangle())
            .position(x:12+width*CGFloat(index)/4,y:12+height*CGFloat(1-output))
            .onTapGesture{point=index}
            .gesture(DragGesture(minimumDistance:1,coordinateSpace:.named("curveGraph")).onChanged{event in
                if !dragging{store.beginGesture();dragging=true};point=index
                setParameter("life.adjust.curves",channel+String(index),Double(1-(event.location.y-12)/height))
            }.onEnded{_ in if dragging{store.endGesture();dragging=false}})
            .accessibilityElement().accessibilityLabel("\(channel.capitalized) curve, \(index*25) percent input")
            .accessibilityValue(String(format:"%.3f output",output))
            .accessibilityAdjustableAction{direction in setParameter("life.adjust.curves",channel+String(index),output+(direction == .increment ? 0.02 : -0.02))}
    }
    private func control(_ name:String,parameter:String,range:ClosedRange<Double>,id:String)->some View {
        VStack(spacing:3){HStack{Text(name).font(.caption);Spacer();TextField(name,value:Binding(get:{value(id,parameter)},set:{setParameter(id,parameter,$0)}),format:.number.precision(.fractionLength(0...3))).textFieldStyle(.roundedBorder).frame(width:64).accessibilityLabel("\(name) value")}
            Slider(value:Binding(get:{value(id,parameter)},set:{setParameter(id,parameter,$0)}),in:range,onEditingChanged:{active in if active{store.beginGesture()}else{store.endGesture()}}).accessibilityLabel(name)
        }
    }
    func value(_ id:String,_ key:String)->Double {
        store.selectedClip?.effects?.first{$0.stableID==id}?.parameters[key] ?? NativeEffectRegistry.definition(for:id)?.parameters.first{$0.name==key}?.defaultValue ?? 0
    }
    func setParameter(_ id:String,_ key:String,_ requested:Double){
        guard requested.isFinite,let parameter=NativeEffectRegistry.definition(for:id)?.parameters.first(where:{$0.name==key}) else{return}
        var number=max(parameter.range.lowerBound,min(parameter.range.upperBound,requested))
        if id=="life.adjust.levels" {
            if key=="black"{number=min(number,value(id,"white")-0.01)}
            if key=="white"{number=max(number,value(id,"black")+0.01)}
        }
        let final=number
        store.editSelected{clip in var effects=clip.effects ?? [];if let index=effects.firstIndex(where:{$0.stableID==id}){effects[index].parameters[key]=final}else{var effect=NativeEffectRegistry.make(id);effect.parameters[key]=final;effects.append(effect)};clip.effects=effects}
    }
    func reset(_ id:String){store.editSelected{$0.effects?.removeAll{$0.stableID==id}}}
}
