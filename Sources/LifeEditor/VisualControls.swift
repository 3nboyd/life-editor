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
            HStack{color("Text",\.color);color("Background",\.background)}
            HStack{Text("Round");Slider(value:Binding(get:{store.selectedClip?.title?.style?.cornerRadius ?? 0},set:{v in update{$0.cornerRadius=v}}),in:0...0.1).accessibilityLabel("Background corner radius")}
            HStack{Text("Outline");Slider(value:Binding(get:{store.selectedClip?.title?.style?.outlineWidth ?? 0},set:{v in update{$0.outlineWidth=v}}),in:0...10).accessibilityLabel("Text outline width")}
        }
    }
    private func update(_ change:(inout TitleStyle)->Void){store.editSelected{clip in var style=clip.title?.style ?? TitleStyle();change(&style);clip.title?.style=style}}
    private func color(_ label:String,_ key:WritableKeyPath<TitleStyle,RGBAColor>)->some View{
        ColorPicker(label,selection:Binding(get:{let c=(store.selectedClip?.title?.style ?? .init())[keyPath:key];return Color(.sRGB,red:c.red,green:c.green,blue:c.blue,opacity:c.alpha)},set:{v in
            guard let rgb=NSColor(v).usingColorSpace(.sRGB) else{return}
            update{$0[keyPath:key] = .init(red:rgb.redComponent,green:rgb.greenComponent,blue:rgb.blueComponent,alpha:rgb.alphaComponent)}
        }),supportsOpacity:true)
    }
}
