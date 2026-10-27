import SwiftUI
import LifeCore

struct MulticamCutControls:View {
    @ObservedObject var store:EditorStore
    @State private var audio=false
    @State private var expanded=false
    private var cuts:[MulticamCut]{audio ? (store.multicamGroup?.audioCuts ?? []):(store.multicamGroup?.cuts ?? [])}
    var body:some View{
        if let group=store.multicamGroup{
            DisclosureGroup("Cuts",isExpanded:$expanded){
                VStack(spacing:10){
                    Picker("Cuts",selection:$audio){Text("Video").tag(false);Text("Audio").tag(true)}.pickerStyle(.segmented)
                    LazyVStack(spacing:8){ForEach(cuts){cut in
                        HStack(spacing:6){
                            Button{store.seek(cut.time)}label:{Image(systemName:audio ? "waveform":"video")}.help("Go to cut").accessibilityLabel("Go to cut")
                            TextField("Seconds",value:Binding(get:{cuts.first(where:{$0.id==cut.id})?.time.seconds ?? cut.time.seconds},set:{store.editMulticamCut(cut.id,audio:audio,seconds:$0,assetID:nil)}),format:.number.precision(.fractionLength(3))).textFieldStyle(.roundedBorder).frame(width:62).accessibilityLabel("Cut time in seconds")
                            Picker("Angle",selection:Binding(get:{cuts.first(where:{$0.id==cut.id})?.angleID ?? cut.angleID},set:{store.editMulticamCut(cut.id,audio:audio,seconds:nil,assetID:$0)})){
                                ForEach(store.document.assets.filter{group.angleAssetIDs.contains($0.id) || (audio && $0.id==group.masterAudioAssetID)}){asset in
                                    Text(asset.url.deletingPathExtension().lastPathComponent).tag(asset.id)
                                }
                                if audio{Text("Silence").tag(MulticamSwitching.silenceAudioID)}
                            }.labelsHidden().accessibilityLabel("Cut source")
                            Button{store.removeMulticamCut(cut.id,audio:audio)}label:{Image(systemName:"minus.circle")}.help("Delete cut").accessibilityLabel("Delete cut")
                        }
                    }}
                }.padding(.top,10).disabled(!store.canRefineMulticamCuts)
            }.padding(.top,12)
        }
    }
}
