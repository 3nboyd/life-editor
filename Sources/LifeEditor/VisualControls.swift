import SwiftUI
@preconcurrency import AVFoundation
import CoreImage
import LifeCore

struct VisualControls:View {
    @ObservedObject var store:EditorStore
    @State private var expanded=false
    @State private var source:CropSize?
    @State private var dimensionsError:String?
    @State private var aspect:CropAspect = .free
    @State private var straightenBase:Double=0
    @State private var straightenAngle:Double=0
    private var visual:VisualTransform{store.selectedClip?.visual ?? .init()}
    private var canvas:CropSize{.init(width:Double(store.document.sequence.settings.width),height:Double(store.document.sequence.settings.height))}
    private var sourceKey:String {
        let asset=store.document.assets.first{$0.id==store.selectedClip?.assetID}
        return "\(store.selection?.uuidString ?? "")|\(asset?.preparedURL?.absoluteString ?? asset?.url.absoluteString ?? "canvas")|\(canvas.width)x\(canvas.height)"
    }
    var body:some View {
        VStack(spacing:8){
            HStack{
                Picker("Crop",selection:Binding(get:{aspect},set:{value in setAspect(value)})){
                    ForEach(CropAspect.allCases,id:\.self){Text($0.rawValue).tag($0)}
                }.help("Apply a source crop ratio; Free leaves edges independent").disabled(source==nil)
                Button{aspect = .free;store.editSelected{$0.visual=CropGeometry.resettingCrop(in:$0.visual ?? .init())}}label:{Image(systemName:"arrow.counterclockwise").frame(width:24,height:24)}.help("Reset crop").accessibilityLabel("Reset crop")
                if let dimensionsError{Image(systemName:"exclamationmark.triangle").foregroundStyle(.orange).help(dimensionsError).accessibilityLabel(dimensionsError)}
            }
            HStack{
                Button{place(.fit)}label:{Label("Fit",systemImage:"arrow.down.right.and.arrow.up.left")}.help("Fit the rotated crop inside the canvas").accessibilityLabel("Fit cropped image")
                Button{place(.fill)}label:{Label("Fill",systemImage:"arrow.up.left.and.arrow.down.right")}.help("Fill the canvas with the rotated crop").accessibilityLabel("Fill canvas")
                Spacer()
            }.disabled(source==nil)
            HStack{
                Text("Straighten")
                Slider(value:Binding(get:{straightenAngle},set:{angle in straightenAngle=angle;store.editSelected{clip in var v=clip.visual ?? .init();v.rotationDegrees=straightenBase+angle;clip.visual=v}}),in:-45...45,onEditingChanged:{editing in if editing{store.beginGesture()}else{store.endGesture()}}).accessibilityLabel("Straighten angle")
                Text(String(format:"%+.1f°",straightenAngle)).font(.caption.monospacedDigit()).frame(width:46)
            }
            DisclosureGroup("Transform",isExpanded:$expanded){
                VStack(spacing:8){
                    HStack{field("X",\.x);field("Y",\.y)}
                    HStack{field("Scale X",\.scaleX);field("Y",\.scaleY)}
                    field("Rotate",\.rotationDegrees)
                    HStack{
                        Button{store.editSelected{clip in var v=clip.visual ?? .init();v.flipHorizontal.toggle();clip.visual=v}}label:{Image(systemName:"arrow.left.and.right").frame(width:24,height:24)}.help("Flip horizontal").accessibilityLabel("Flip horizontal")
                        Button{store.editSelected{clip in var v=clip.visual ?? .init();v.flipVertical.toggle();clip.visual=v}}label:{Image(systemName:"arrow.up.and.down").frame(width:24,height:24)}.help("Flip vertical").accessibilityLabel("Flip vertical")
                        Spacer();Button("Reset"){aspect = .free;store.editSelected{$0.visual=nil}}
                    }
                    HStack{field("Crop L",\.cropLeft);field("R",\.cropRight)}
                    HStack{field("Crop T",\.cropTop);field("B",\.cropBottom)}
                }.padding(.top,8)
            }
        }
        .task(id:sourceKey){await loadDimensions()}
        .onAppear{syncStraighten(visual.rotationDegrees)}
        .onChange(of:store.selection){_,_ in aspect = .free;syncStraighten(visual.rotationDegrees)}
        .onChange(of:store.selectedClip?.visual?.rotationDegrees){_,rotation in
            let value=rotation ?? 0
            if abs(value-straightenBase-straightenAngle)>0.000001{syncStraighten(value)}
        }
        .onChange(of:store.selectedClip?.visual){_,value in
            guard let source,let ratio=aspect.ratio else{return}
            let v=value ?? .init(),actual=source.width*(1-v.cropLeft-v.cropRight)/(source.height*(1-v.cropTop-v.cropBottom))
            if abs(actual-ratio)>0.0001{aspect = .free}
        }
    }
    private func syncStraighten(_ rotation:Double){let parts=CropGeometry.straightenComponents(rotation);straightenBase=parts.base;straightenAngle=parts.angle}
    private func setAspect(_ value:CropAspect){
        aspect=value
        guard let source,value != .free else{return}
        do{let updated=try CropGeometry.applying(value,to:visual,source:source);store.editSelected{$0.visual=updated}}
        catch{store.error=error.localizedDescription}
    }
    private func place(_ mode:CropFitMode){
        guard let source else{return}
        do{let updated=try CropGeometry.placing(visual,source:source,canvas:canvas,mode:mode);store.editSelected{$0.visual=updated}}
        catch{store.error=error.localizedDescription}
    }
    private func loadDimensions()async {
        source=nil;dimensionsError=nil
        guard let clip=store.selectedClip else{return}
        let asset=(clip.title != nil || clip.graphic != nil) ? nil:store.document.assets.first{$0.id==clip.assetID}
        if clip.title == nil,clip.graphic == nil,asset == nil{dimensionsError="Missing media";return}
        let canvas=canvas
        let task=Task.detached(priority:.userInitiated){try await Self.sourceDimensions(asset:asset,canvas:canvas)}
        do{let size=try await withTaskCancellationHandler{try await task.value}onCancel:{task.cancel()};try Task.checkCancellation();source=size}
        catch{if !Task.isCancelled{dimensionsError=error.localizedDescription}}
    }
    nonisolated static func sourceDimensions(asset:MediaAsset?,canvas:CropSize)async throws->CropSize {
        try Task.checkCancellation()
        guard let asset else{guard canvas.isValid else{throw CropGeometryError.dimensions};return canvas}
        let url=asset.preparedURL ?? asset.url
        let size:CropSize
        if asset.kind == .image {
            guard let image=CIImage(contentsOf:url,options:[.applyOrientationProperty:true]) else{throw CropGeometryError.dimensions}
            size = .init(width:image.extent.width,height:image.extent.height)
        }else{
            let avAsset=AVURLAsset(url:url)
            defer{withExtendedLifetime(avAsset){}}
            guard let track=try await avAsset.loadTracks(withMediaType:.video).first else{throw CropGeometryError.dimensions}
            let natural=try await track.load(.naturalSize),transform=try await track.load(.preferredTransform)
            let extent=CGRect(origin:.zero,size:natural).applying(transform)
            size = .init(width:abs(extent.width),height:abs(extent.height))
        }
        try Task.checkCancellation();guard size.isValid else{throw CropGeometryError.dimensions};return size
    }
    func field(_ label:String,_ key:WritableKeyPath<VisualTransform,Double>)->some View {
        HStack{Text(label);TextField(label,value:Binding(get:{visual[keyPath:key]},set:{value in store.editSelected{clip in var visual=clip.visual ?? .init();visual[keyPath:key]=value;clip.visual=visual}}),format:.number.precision(.fractionLength(2))).textFieldStyle(.roundedBorder).accessibilityLabel(label)}
    }
}
struct TitleControls:View {
    @ObservedObject var store:EditorStore
    var body:some View {
        VStack(spacing:10){
            TitleLayoutPresetControls(store:store)
            TextPresetControls(store:store)
            Picker("Font",selection:Binding(get:{store.selectedClip?.title?.style?.fontName ?? "Helvetica-Bold"},set:{name in update{$0.fontName=name}})){
                ForEach([("HelveticaNeue","Plain"),("Helvetica-Bold","Bold"),("HelveticaNeue-CondensedBold","Condensed"),("Georgia","Serif"),("Noteworthy","Handwritten"),("Menlo","Typewriter")],id:\.0){name,label in Text(label).tag(name)}
                if let current=store.selectedClip?.title?.style?.fontName,!["HelveticaNeue","Helvetica-Bold","HelveticaNeue-CondensedBold","Georgia","Noteworthy","Menlo"].contains(current){Text(current).tag(current)}
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
            TitleTypographyControls(store:store)
            TitleBackgroundControls(store:store)
            HStack{Text("Outline");Slider(value:Binding(get:{store.selectedClip?.title?.style?.outlineWidth ?? 0},set:{v in update{$0.outlineWidth=v}}),in:0...10).accessibilityLabel("Text outline width")}
        }
    }
    private func update(_ change:(inout TitleStyle)->Void){store.editSelected{clip in var style=clip.title?.style ?? TitleStyle();change(&style);clip.title?.style=style}}
    private func color(_ label:String,_ key:WritableKeyPath<TitleStyle,RGBAColor>)->some View{
        SharedColorPicker(label:label,color:Binding(get:{(store.selectedClip?.title?.style ?? .init())[keyPath:key]},set:{value in update{$0[keyPath:key]=value}}),store:store)
    }
}
