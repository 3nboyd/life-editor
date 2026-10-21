import SwiftUI
import LifeCore

struct DrawingControls:View {
    @ObservedObject var store:EditorStore
    var body:some View {
        VStack(alignment:.leading,spacing:14){
            Picker("Tool",selection:$store.drawingMode){Image(systemName:"pencil.tip").tag(1).accessibilityLabel("Pen");Image(systemName:"highlighter").tag(2).accessibilityLabel("Highlighter");Image(systemName:"eraser").tag(3).accessibilityLabel("Eraser")}.pickerStyle(.segmented)
            ColorPicker("Color",selection:Binding(get:{let c=store.drawingColor;return Color(.sRGB,red:c.red,green:c.green,blue:c.blue,opacity:c.alpha)},set:{v in guard let c=NSColor(v).usingColorSpace(.sRGB) else{return};store.drawingColor = .init(red:c.redComponent,green:c.greenComponent,blue:c.blueComponent,alpha:c.alphaComponent)}),supportsOpacity:true)
            HStack{Text("Width");Slider(value:$store.drawingWidth,in:0.001...0.05).accessibilityLabel("Stroke width")}
            if let clip=store.selectedClip,case .drawing(let drawing)=clip.graphic {
                Text("\(drawing.strokes.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button("Clear"){store.editSelected{$0.graphic = .drawing(.init())}}
            }
            Button("Done"){store.drawingMode=0;store.panel=nil}
        }
    }
}
