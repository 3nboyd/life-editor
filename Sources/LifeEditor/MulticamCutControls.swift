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
                }.padding(.top,10).disabled(store.playing || store.checkingCameraAudio)
            }.padding(.top,12)
        }
    }
}

extension EditorStore {
    func editMulticamCut(_ id:UUID,audio:Bool,seconds:Double?,assetID:UUID?){
        guard var group=multicamGroup else{return}
        var cuts=audio ? group.audioCuts ?? []:group.cuts
        guard let index=cuts.firstIndex(where:{$0.id==id}) else{return}
        if let seconds{
            guard seconds.isFinite,(0...document.sequence.duration.seconds).contains(seconds) else{error="Keep cuts inside the sequence.";return}
            do{let position=try document.sequence.settings.frameRate.checkedQuantized(time(seconds,audio:true));guard !cuts.contains(where:{$0.id != id && $0.time==position}) else{error="A cut already exists at this frame.";return};cuts[index].time=position}catch{self.error=Self.message(error);return}
        }
        if let assetID{cuts[index].angleID=assetID}
        let source=cuts[index].angleID,position=cuts[index].time
        if source != MulticamSwitching.silenceAudioID{
            guard (!audio || cameraAudioIDs.contains(source)),document.sequence.tracks.flatMap(\.clips).contains(where:{$0.assetID==source && $0.start<=position && position<$0.end}) else{error="This source is unavailable at the cut.";return}
        }
        cuts.sort{$0.time<$1.time}
        if audio{group.audioCuts=cuts}else{group.cuts=cuts}
        var next=document;next.sequence.multicamGroups[next.sequence.multicamGroups.count-1]=group;replace(next)
    }
    func removeMulticamCut(_ id:UUID,audio:Bool){
        guard var group=multicamGroup else{return}
        if audio{group.audioCuts?.removeAll{$0.id==id}}else{group.cuts.removeAll{$0.id==id}}
        var next=document;next.sequence.multicamGroups[next.sequence.multicamGroups.count-1]=group;replace(next)
    }
}
