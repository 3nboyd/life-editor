import SwiftUI
import LifeCore
import LifeMedia

struct TitleBackgroundControls:View {
    @ObservedObject var store:EditorStore
    @State private var expanded=false
    @State private var shadowExpanded=false
    init(store:EditorStore,expanded:Bool=false,shadowExpanded:Bool=false){self.store=store;_expanded=State(initialValue:expanded);_shadowExpanded=State(initialValue:shadowExpanded)}
    @State private var thumbnails:[TitleBackgroundShape:CGImage]=[:]
    private var current:TitleBackgroundStyle {
        if let background=store.selectedClip?.title?.style?.backgroundStyle{return background}
        let title=store.selectedClip?.title,style=title?.style ?? .init()
        return .init(shape:style.background.alpha==0 ? .none:(style.cornerRadius==0 ? .square:.rounded),padding:max(2,(title?.fontSize ?? 64)*0.25),cornerRadius:min(1,style.cornerRadius*2))
    }
    private var color:RGBAColor {store.selectedClip?.title?.style?.background ?? .clear}
    private var signature:String {String(describing:current)+String(describing:color)}
    var body:some View {
        DisclosureGroup("Background",isExpanded:$expanded){
            VStack(spacing:10){
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:6){
                    ForEach(TitleBackgroundShape.allCases,id:\.self){shape in
                        Button{selectShape(shape)}label:{
                            VStack(spacing:2){
                                if let image=thumbnails[shape]{Image(decorative:image,scale:1).resizable().scaledToFit().frame(height:45)}else{Color.clear.frame(height:45)}
                                HStack(spacing:3){if current.shape==shape{Image(systemName:"checkmark").font(.caption2)};Text(shape.label).font(.caption)}
                            }.frame(maxWidth:.infinity).padding(4).background(.white.opacity(current.shape==shape ? 0.12:0.035),in:RoundedRectangle(cornerRadius:5))
                        }.buttonStyle(.plain).help(shape.label+" background").accessibilityLabel(shape.label+" background").accessibilityAddTraits(current.shape==shape ? .isSelected:[])
                    }
                }
                if current.shape != .none {
                    slider("Padding",\.padding,0...100)
                    if current.shape == .rounded || current.shape == .speechBubble{slider("Round",\.cornerRadius,0...1)}
                    slider("Border",\.borderWidth,0...20)
                    swatch("Border color",\.borderColor)
                }
                DisclosureGroup("Shadow",isExpanded:$shadowExpanded){
                    VStack(spacing:8){
                        swatch("Shadow color",\.shadowColor)
                        slider("Blur",\.shadowBlur,0...100)
                        slider("X",\.shadowOffsetX,-100...100)
                        slider("Y",\.shadowOffsetY,-100...100)
                    }.padding(.top,6)
                }
            }.padding(.top,8)
        }.task(id:signature){
            let appearance=current,fill=color
            var rendered:[TitleBackgroundShape:CGImage]=[:]
            for shape in TitleBackgroundShape.allCases {
                guard !Task.isCancelled else{return}
                var style=appearance;style.shape=shape
                if let image=try? await TitleThumbnails.shared.image(background:style,color:fill.alpha==0 && shape != .none ? Self.defaultFill:fill){rendered[shape]=image}
            }
            guard !Task.isCancelled else{return};thumbnails=rendered
        }
    }
    private static let defaultFill=RGBAColor(red:0.16,green:0.24,blue:0.28)
    func selectShape(_ shape:TitleBackgroundShape){
        var appearance=current;appearance.shape=shape
        store.editSelected{clip in
            guard var title=clip.title else{return};var style=title.style ?? .init()
            style.backgroundStyle=appearance
            if shape != .none,style.background.alpha==0{style.background=Self.defaultFill}
            title.style=style;clip.title=title
        }
    }
    func update(_ change:(inout TitleBackgroundStyle)->Void){
        var appearance=current;change(&appearance)
        guard appearance.isValid else{return}
        store.editSelected{clip in guard var title=clip.title else{return};var style=title.style ?? .init();style.backgroundStyle=appearance;title.style=style;clip.title=title}
    }
    private func slider(_ label:String,_ key:WritableKeyPath<TitleBackgroundStyle,Double>,_ range:ClosedRange<Double>)->some View{
        HStack{Text(label).font(.caption).frame(width:44,alignment:.leading)
            Slider(value:Binding(get:{current[keyPath:key]},set:{value in update{$0[keyPath:key]=value}}),in:min(range.lowerBound,current[keyPath:key])...max(range.upperBound,current[keyPath:key]),onEditingChanged:{active in if active{store.beginGesture()}else{store.endGesture()}}).accessibilityLabel("Title background "+label.lowercased())
            TextField(label,value:Binding(get:{current[keyPath:key]},set:{value in update{$0[keyPath:key]=value}}),format:.number.precision(.fractionLength(0...1))).textFieldStyle(.roundedBorder).frame(width:60).accessibilityLabel("Title background "+label.lowercased()+" value")
        }
    }
    private func swatch(_ label:String,_ key:WritableKeyPath<TitleBackgroundStyle,RGBAColor>)->some View {
        SharedColorPicker(label:label,color:Binding(get:{current[keyPath:key]},set:{value in update{$0[keyPath:key]=value}}),store:store)
    }
}
