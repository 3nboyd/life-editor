import SwiftUI
import LifeCore

struct VisualControls:View {
    @ObservedObject var store:EditorStore
    @State private var expanded=false
    var body:some View {
        DisclosureGroup("Transform",isExpanded:$expanded){
            VStack(spacing:8){
                HStack{field("X",\.x);field("Y",\.y)}
                HStack{field("Scale X",\.scaleX);field("Y",\.scaleY)}
                field("Rotate",\.rotationDegrees)
                HStack{
                    Button("↔"){store.editSelected{clip in var v=clip.visual ?? .init();v.flipHorizontal.toggle();clip.visual=v}}.help("Flip horizontal").accessibilityLabel("Flip horizontal")
                    Button("↕"){store.editSelected{clip in var v=clip.visual ?? .init();v.flipVertical.toggle();clip.visual=v}}.help("Flip vertical").accessibilityLabel("Flip vertical")
                    Spacer();Button("Reset"){store.editSelected{$0.visual=nil}}
                }
                HStack{field("Crop L",\.cropLeft);field("R",\.cropRight)}
                HStack{field("Crop T",\.cropTop);field("B",\.cropBottom)}
            }.padding(.top,8)
        }
    }
    func field(_ label:String,_ key:WritableKeyPath<VisualTransform,Double>)->some View {
        HStack{Text(label);TextField(label,value:Binding(get:{(store.selectedClip?.visual ?? .init())[keyPath:key]},set:{value in store.editSelected{clip in var visual=clip.visual ?? .init();visual[keyPath:key]=value;clip.visual=visual}}),format:.number.precision(.fractionLength(2))).textFieldStyle(.roundedBorder).accessibilityLabel(label)}
    }
}
struct TitleControls:View {
    @ObservedObject var store:EditorStore
    var body:some View {
        VStack(spacing:10){
            Picker("Font",selection:Binding(get:{store.selectedClip?.title?.style?.fontName ?? "Helvetica-Bold"},set:{name in update{$0.fontName=name}})){
                ForEach([("HelveticaNeue","Plain"),("Helvetica-Bold","Bold"),("HelveticaNeue-CondensedBold","Condensed"),("Georgia","Serif"),("Noteworthy","Handwritten"),("Menlo","Typewriter")],id:\.0){name,label in Text(label).tag(name)}
            }
            if let name=store.selectedClip?.title?.style?.fontName,NSFont(name:name,size:12)==nil{Label("Missing font",systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange)}
            Picker("Animate",selection:Binding(get:{store.selectedClip?.title?.animation?.kind.rawValue ?? ""},set:{value in
                store.editSelected{clip in if let kind=TitleAnimationKind(rawValue:value){var animation=clip.title?.animation ?? TitleAnimation(kind:kind);animation.kind=kind;clip.title?.animation=animation}else{clip.title?.animation=nil}}
            })){
                Text("None").tag("")
                ForEach(TitleAnimationKind.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0.rawValue)}
            }
            if store.selectedClip?.title?.animation != nil{
                HStack{Text("Duration");TextField("Seconds",value:Binding(get:{store.selectedClip?.title?.animation?.duration ?? 0.5},set:{value in guard value.isFinite,(0.05...10).contains(value) else{return};store.editSelected{$0.title?.animation?.duration=value}}),format:.number.precision(.fractionLength(2))).textFieldStyle(.roundedBorder).accessibilityLabel("Title entrance duration seconds")}
                if store.selectedClip?.title?.animation?.kind == .slide{
                    Picker("Direction",selection:Binding(get:{store.selectedClip?.title?.animation?.direction ?? 0},set:{value in store.editSelected{$0.title?.animation?.direction=value}})){
                        Image(systemName:"arrow.left").tag(0);Image(systemName:"arrow.right").tag(1);Image(systemName:"arrow.up").tag(2);Image(systemName:"arrow.down").tag(3)
                    }.pickerStyle(.segmented).accessibilityLabel("Title entrance direction")
                }
            }
            HStack{color("Text",\.color);color("Background",\.background)}
            HStack{Text("Round");Slider(value:Binding(get:{store.selectedClip?.title?.style?.cornerRadius ?? 0},set:{v in update{$0.cornerRadius=v}}),in:0...0.1).accessibilityLabel("Background corner radius")}
            HStack{Text("Outline");Slider(value:Binding(get:{store.selectedClip?.title?.style?.outlineWidth ?? 0},set:{v in update{$0.outlineWidth=v}}),in:0...10).accessibilityLabel("Text outline width")}
        }
    }
    private func update(_ change:(inout TitleStyle)->Void){store.editSelected{clip in var style=clip.title?.style ?? TitleStyle();change(&style);clip.title?.style=style}}
    private func color(_ label:String,_ key:WritableKeyPath<TitleStyle,RGBAColor>)->some View{
        SharedColorPicker(label:label,color:Binding(get:{(store.selectedClip?.title?.style ?? .init())[keyPath:key]},set:{value in update{$0[keyPath:key]=value}}),store:store)
    }
}
