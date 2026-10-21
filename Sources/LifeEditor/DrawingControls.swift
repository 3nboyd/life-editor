import SwiftUI
import LifeCore

struct DrawingControls:View {
    @ObservedObject var store:EditorStore
    var body:some View {
        VStack(alignment:.leading,spacing:14){
            Picker("Tool",selection:$store.drawingMode){Image(systemName:"pencil.tip").tag(1).accessibilityLabel("Pen");Image(systemName:"highlighter").tag(2).accessibilityLabel("Highlighter");Image(systemName:"eraser").tag(3).accessibilityLabel("Eraser")}.pickerStyle(.segmented)
            SharedColorPicker(label:"Color",color:$store.drawingColor,store:store)
            HStack{Text("Width");Slider(value:$store.drawingWidth,in:0.001...0.05).accessibilityLabel("Stroke width")}
            if let clip=store.selectedClip,case .drawing(let drawing)=clip.graphic {
                Text("\(drawing.strokes.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button("Clear"){store.editSelected{$0.graphic = .drawing(.init())}}
            }
            Button("Done"){store.drawingMode=0;store.panel=nil}
        }
    }
}
