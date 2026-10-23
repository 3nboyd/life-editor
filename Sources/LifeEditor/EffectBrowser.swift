import SwiftUI
import LifeCore
import LifeMedia

struct EffectBrowser:View {
    @ObservedObject var store:EditorStore
    @State private var category=0
    @State private var thumbnails:[String:CGImage]=[:]
    @State private var loading=false
    @State private var requestID=UUID()
    @State private var appliedExpanded=false
    @State private var layerControls=false
    @AppStorage("favoriteEffects") private var favorites=""
    private var asset:MediaAsset?{store.document.assets.first{$0.id==store.selectedClip?.assetID && $0.kind != .audio}}
    var body:some View {
        VStack(spacing:12){
            HStack{Picker("Effects",selection:$category){if !store.selectedIsAdjustment{Text("Transitions").tag(2)};Text("Filters").tag(0);Text("Adjust").tag(1)}.pickerStyle(.segmented)
                if store.selectedIsAdjustment{
                    Button{layerControls.toggle()}label:{Image(systemName:"slider.horizontal.3").frame(width:24,height:24)}.help("Layer timing and opacity").accessibilityLabel("Layer timing and opacity").popover(isPresented:$layerControls){
                        VStack(spacing:12){
                            HStack{Text("Start");TextField("Seconds",value:Binding(get:{store.selectedClip?.start.seconds ?? 0},set:{store.setClipStart($0)}),format:.number.precision(.fractionLength(3))).textFieldStyle(.roundedBorder).accessibilityLabel("Adjustment layer start seconds")}
                            HStack{Text("Duration");TextField("Seconds",value:Binding(get:{store.selectedClip?.duration.seconds ?? 0},set:{store.setAdjustmentDuration($0)}),format:.number.precision(.fractionLength(3))).textFieldStyle(.roundedBorder).accessibilityLabel("Adjustment layer duration seconds")}
                            AutomationControls(store:store)
                        }.padding(16).frame(width:280)
                    }
                }
                if category==1{Button{store.addAdjustmentLayer()}label:{Image(systemName:"plus.square.on.square").frame(width:24,height:24)}.help("Add timed adjustment layer").accessibilityLabel("Add adjustment layer")}
            }
            if category==2 {TransitionsBrowser(store:store)}
            else if !store.selectedAcceptsVisualEffects {Image(systemName:"photo.on.rectangle.angled").font(.largeTitle).foregroundStyle(.secondary).padding().accessibilityLabel("Select a visual clip")}
            else if category==0 {
                if loading {ProgressView().controlSize(.small).accessibilityLabel("Loading effect previews")}
                ScrollView {
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10){
                        ForEach(sortedDefinitions){definition in
                            Button{applyPreset(definition.stableID)}label:{
                                VStack(alignment:.leading,spacing:4){
                                    if let frame=thumbnails[definition.stableID]{Image(decorative:frame,scale:1).resizable().aspectRatio(contentMode:.fill).frame(height:62).clipped().clipShape(RoundedRectangle(cornerRadius:4))}
                                    Text(definition.name).font(.caption).foregroundStyle(.primary).lineLimit(1)
                                }.padding(3).overlay{if store.selectedClip?.effects?.contains(where:{$0.stableID==definition.stableID}) == true {RoundedRectangle(cornerRadius:5).stroke(.white.opacity(0.8),lineWidth:1)}}
                            }.buttonStyle(.plain).help(definition.name).accessibilityLabel(definition.name)
                                .contextMenu {Button(isFavorite(definition.stableID) ? "Unfavorite":"Favorite"){toggleFavorite(definition.stableID)}}
                        }
                    }
                }
                if let effect=store.selectedClip?.effects?.first(where:{$0.stableID.hasPrefix("life.filter.")}){
                    HStack{Text("Strength");Slider(value:Binding(get:{store.selectedClip?.effects?.first(where:{$0.id==effect.id})?.strength ?? 1},set:{value in store.editSelected{clip in if let i=clip.effects?.firstIndex(where:{$0.id==effect.id}){clip.effects?[i].strength=value}}}),in:0...1,onEditingChanged:{active in if active{store.beginGesture()}else{store.endGesture()}}).accessibilityLabel("Filter strength")}
                    HStack{
                        Toggle("Bypass",isOn:Binding(get:{!(store.selectedClip?.effects?.first(where:{$0.id==effect.id})?.isEnabled ?? true)},set:{value in store.editSelected{clip in if let i=clip.effects?.firstIndex(where:{$0.id==effect.id}){clip.effects?[i].isEnabled = !value}}})).toggleStyle(.button)
                        Spacer();Button("Reset"){store.editSelected{$0.effects?.removeAll{$0.stableID.hasPrefix("life.filter.")}}}
                    }
                }
            }else{
                ScrollView{
                    VStack(alignment:.leading,spacing:12){
                        ForEach(NativeEffectRegistry.adjustments){definition in
                            if let parameter=definition.parameters.first {
                                HStack{Text(definition.name);Spacer();Text(String(format:"%.2f",value(definition.stableID,parameter))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)}
                                Slider(value:Binding(get:{value(definition.stableID,parameter)},set:{number in setAdjustment(definition.stableID,number)}),in:parameter.range,onEditingChanged:{active in if active{store.beginGesture()}else{store.endGesture()}}).accessibilityLabel(definition.name)
                            }
                        }
                        Button("Reset"){store.resetAdjustments()}.help("Reset adjustments")
                    }
                }
            }
            if store.selectedAcceptsVisualEffects,category != 2{
                HStack{
                    Button{store.copyEffectSettings()}label:{Image(systemName:"doc.on.doc").frame(width:24,height:24)}.help("Copy effect settings").accessibilityLabel("Copy effect settings")
                    Button{store.pasteEffectSettings()}label:{Image(systemName:"doc.on.clipboard").frame(width:24,height:24)}.help("Paste effect settings").accessibilityLabel("Paste effect settings")
                    Spacer()
                }
                if !(store.selectedClip?.effects ?? []).isEmpty{
                    DisclosureGroup("Applied",isExpanded:$appliedExpanded){
                        ForEach(store.selectedClip?.effects ?? []){effect in
                            HStack{Text(NativeEffectRegistry.definition(for:effect.stableID)?.name ?? effect.stableID).lineLimit(1)
                                if NativeEffectRegistry.definition(for:effect.stableID)==nil{Image(systemName:"exclamationmark.triangle").foregroundStyle(.orange).help("Unavailable effect · \(effect.stableID)").accessibilityLabel("Unavailable effect \(effect.stableID)")}
                                Spacer()
                                Button{store.setEffectEnabled(id:effect.id,enabled:!effect.isEnabled)}label:{Image(systemName:effect.isEnabled ? "eye":"eye.slash").frame(width:24,height:24)}.help(effect.isEnabled ? "Bypass effect":"Enable effect").accessibilityLabel("\(effect.isEnabled ? "Bypass":"Enable") \(NativeEffectRegistry.definition(for:effect.stableID)?.name ?? effect.stableID)").accessibilityValue(effect.isEnabled ? "Enabled":"Bypassed")
                            }
                        }
                    }
                }
            }
        }
            .onAppear{if store.selectedIsAdjustment{category=1}else if store.selectedTransition != nil{category=2}}
            .onChange(of:store.selectedTransition){_,id in if id != nil,!store.selectedIsAdjustment{category=2}}
            .onChange(of:store.selection){_,_ in if store.selectedIsAdjustment,category==2{category=1}}
            .task(id:"\(store.selection?.uuidString ?? "")|\((asset?.preparedURL ?? asset?.url)?.absoluteString ?? "chart")|\(store.selectedClip?.sourceStart.seconds ?? 0)"){await loadThumbnails()}
    }
    private var sortedDefinitions:[EffectDefinition]{NativeEffectRegistry.definitions.sorted{isFavorite($0.stableID) && !isFavorite($1.stableID)}}
    private func isFavorite(_ id:String)->Bool{favorites.split(separator:",").contains(Substring(id))}
    private func toggleFavorite(_ id:String){var all=Set(favorites.split(separator:",").map(String.init));if all.contains(id){all.remove(id)}else{all.insert(id)};favorites=all.sorted().joined(separator:",")}
    func applyPreset(_ id:String){store.editSelected{clip in var effects=clip.effects ?? [];effects.removeAll{$0.stableID.hasPrefix("life.filter.")};effects.append(NativeEffectRegistry.make(id,seed:17));clip.effects=effects}}
    private func value(_ id:String,_ parameter:EffectParameterDefinition)->Double{store.selectedClip?.effects?.first{$0.stableID==id}?.parameters[parameter.name] ?? parameter.defaultValue}
    func setAdjustment(_ id:String,_ number:Double){store.editSelected{clip in var effects=clip.effects ?? [];if let index=effects.firstIndex(where:{$0.stableID==id}){effects[index].parameters["value"]=number}else{var effect=NativeEffectRegistry.make(id);effect.parameters["value"]=number;effects.append(effect)};clip.effects=effects}}
    private func loadThumbnails() async {
        thumbnails=[:];guard store.selectedAcceptsVisualEffects else{return}
        let token=UUID();requestID=token;loading=true;defer{if token==requestID{loading=false}}
        let asset=asset,sourceTime=store.selectedClip?.sourceStart ?? .zero
        let pipeline=MediaPipeline()
        for definition in NativeEffectRegistry.definitions {
            guard !Task.isCancelled else{return}
            do{
                let effects=[NativeEffectRegistry.make(definition.stableID,seed:17)]
                let image:CGImage
                if let asset{image=try await pipeline.thumbnail(asset:asset,at:max(.zero,sourceTime),effects:effects)}
                else{image=try await EffectThumbnails.shared.image(effects:effects)}
                guard !Task.isCancelled,token==requestID else{return};thumbnails[definition.stableID]=image
            }catch{if !Task.isCancelled{store.error=error.localizedDescription};return}
        }
    }
}
