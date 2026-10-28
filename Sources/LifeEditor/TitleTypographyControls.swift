import SwiftUI
import LifeCore

struct TitleTypographyControls:View {
    @ObservedObject var store:EditorStore
    @State private var expanded=false
    var current:TitleTypography {store.selectedClip?.title?.style?.typography ?? .init()}
    var body:some View {
        VStack(spacing:8){
            Picker("Alignment",selection:Binding(get:{current.alignment},set:{value in update{$0.alignment=value}})){
                ForEach(TitleAlignment.allCases,id:\.self){alignment in
                    Image(systemName:"text.align"+alignment.rawValue).tag(alignment)
                        .accessibilityLabel(alignment.rawValue.capitalized)
                        .help("Align "+alignment.rawValue)
                }
            }.pickerStyle(.segmented).accessibilityLabel("Text alignment")
            DisclosureGroup("Spacing",isExpanded:$expanded){
                VStack(spacing:8){
                    spacing("Letters",key:\.letterSpacing,range:-20...100)
                    spacing("Lines",key:\.lineSpacing,range:0...512)
                }.padding(.top,6)
            }
        }
    }
    private func spacing(_ label:String,key:WritableKeyPath<TitleTypography,Double>,range:ClosedRange<Double>)->some View {
        VStack(spacing:3){
            HStack{
                Text(label);Spacer()
                TextField(label,value:Binding(get:{current[keyPath:key]},set:{value in update{$0[keyPath:key]=value}}),format:.number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder).frame(width:60).accessibilityLabel(label+" spacing points")
            }
            Slider(value:Binding(get:{current[keyPath:key]},set:{value in update{$0[keyPath:key]=value}}),in:range,onEditingChanged:{editing in if editing{store.beginGesture()}else{store.endGesture()}})
                .accessibilityLabel(label+" spacing").help(label+" spacing")
        }
    }
    func update(_ change:(inout TitleTypography)->Void){
        var value=current;change(&value);guard value.isValid else{return}
        store.editSelected{clip in
            var style=clip.title?.style ?? .init();style.typography=value;clip.title?.style=style
        }
    }
}
