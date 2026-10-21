import SwiftUI
import LifeCore
import LifeMedia

struct EffectBrowser:View {
    @ObservedObject var store:EditorStore
    @State private var category=0
    @State private var thumbnails:[String:CGImage]=[:]
    @State private var loading=false
    @AppStorage("favoriteEffects") private var favorites=""
    private var asset:MediaAsset?{store.document.assets.first{$0.id==store.selectedClip?.assetID && $0.kind != .audio}}
    var body:some View {
        VStack(spacing:12){
            Picker("Effects",selection:$category){Text("Transitions").tag(2);Text("Filters").tag(0);Text("Adjust").tag(1)}.pickerStyle(.segmented)
            if category==2 {TransitionsBrowser(store:store)}
            else if asset == nil {Image(systemName:"photo.on.rectangle.angled").font(.largeTitle).foregroundStyle(.secondary).padding().accessibilityLabel("Select a visual clip")}
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
                        Button("Reset"){store.editSelected{$0.effects?.removeAll{$0.stableID.hasPrefix("life.adjust.")}}}
                    }
                }
            }
        }
            .onAppear{if store.selectedTransition != nil{category=2}}
            .onChange(of:store.selectedTransition){_,id in if id != nil{category=2}}
            .task(id:asset?.preparedURL ?? asset?.url){await loadThumbnails()}
    }
    private var sortedDefinitions:[EffectDefinition]{NativeEffectRegistry.definitions.sorted{isFavorite($0.stableID) && !isFavorite($1.stableID)}}
    private func isFavorite(_ id:String)->Bool{favorites.split(separator:",").contains(Substring(id))}
    private func toggleFavorite(_ id:String){var all=Set(favorites.split(separator:",").map(String.init));if all.contains(id){all.remove(id)}else{all.insert(id)};favorites=all.sorted().joined(separator:",")}
    private func applyPreset(_ id:String){store.editSelected{clip in var effects=clip.effects ?? [];effects.removeAll{$0.stableID.hasPrefix("life.filter.")};effects.append(NativeEffectRegistry.make(id,seed:17));clip.effects=effects}}
    private func value(_ id:String,_ parameter:EffectParameterDefinition)->Double{store.selectedClip?.effects?.first{$0.stableID==id}?.parameters[parameter.name] ?? parameter.defaultValue}
    private func setAdjustment(_ id:String,_ number:Double){store.editSelected{clip in var effects=clip.effects ?? [];if let index=effects.firstIndex(where:{$0.stableID==id}){effects[index].parameters["value"]=number}else{var effect=NativeEffectRegistry.make(id);effect.parameters["value"]=number;effects.append(effect)};clip.effects=effects}}
    private func loadThumbnails() async {
        thumbnails=[:];guard let asset else{return};loading=true;defer{loading=false}
        let pipeline=MediaPipeline()
        for definition in NativeEffectRegistry.definitions {
            guard !Task.isCancelled else{return}
            do{let image=try await pipeline.thumbnail(asset:asset,at:store.selectedClip?.sourceStart ?? .zero,effects:[NativeEffectRegistry.make(definition.stableID,seed:17)]);guard !Task.isCancelled else{return};thumbnails[definition.stableID]=image}
            catch{if !Task.isCancelled{store.error=error.localizedDescription};return}
        }
    }
}
