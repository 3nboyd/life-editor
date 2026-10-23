import SwiftUI
import LifeCore

extension EditorStore {
    func prepareMarkerSynchronization(reference:UUID,target:UUID){
        guard !playing,placementProposal==nil else{error="Pause playback and finish the placement preview first.";return}
        do{
            let baseline=document
            let alignment=try MarkerSynchronization.alignment(referenceMarkerID:reference,targetMarkerID:target,in:baseline)
            guard let group=multicamGroup else{throw DocumentError.clipNotFound}
            let members=Set(group.angleAssetIDs+[group.masterAudioAssetID].compactMap{$0})
            guard members.contains(alignment.referenceAssetID),members.contains(alignment.targetAssetID) else{throw MarkerSynchronizationError.sourceMarker}
            guard baseline.sequence.tracks.flatMap(\.clips).filter({$0.assetID.map(members.contains)==true}).allSatisfy({$0.speed==1 && $0.freezeFrame==nil}) else{throw MarkerSynchronizationError.retimed}
            cancelSynchronization()
            _=installSynchronizationResults([.init(assetID:alignment.targetAssetID,offset:alignment.offset.seconds,confidence:1,note:"Marker",exactOffset:alignment.offset)],referenceID:alignment.referenceAssetID,baseline:baseline)
        }catch{self.error=Self.message(error)}
    }
}
struct MarkerSynchronizationControls:View {
    @ObservedObject var store:EditorStore
    @State private var showing=false
    @State private var reference:UUID?
    @State private var target:UUID?
    private var markers:[Marker]{
        guard let group=store.multicamGroup else{return []}
        let ids=Set(group.angleAssetIDs+[group.masterAudioAssetID].compactMap{$0})
        let clips=store.document.sequence.tracks.flatMap(\.clips)
        return store.document.sequence.markers.filter{marker in clips.contains{$0.id==marker.clipID && $0.assetID.map(ids.contains)==true}}
    }
    var body:some View{
        Button{
            reference=markers.first?.id
            target=markers.first(where:{assetID(for:$0) != markers.first.flatMap(assetID(for:))})?.id
            showing=true
        }label:{Label("Markers",systemImage:"bookmark")}
        .help("Align clip marker starts").accessibilityLabel("Synchronize using clip markers")
        .disabled(store.playing || store.placementProposal != nil)
        .popover(isPresented:$showing){
            VStack(alignment:.leading,spacing:10){
                picker("Reference",selection:$reference)
                picker("Align",selection:$target)
                Button("Review"){
                    if let reference,let target{store.prepareMarkerSynchronization(reference:reference,target:target);showing=false}
                }.disabled(reference==nil || target==nil || reference==target).help("Review marker alignment before applying")
            }.padding(12).frame(width:280)
        }
    }
    private func assetID(for marker:Marker)->UUID?{store.document.sequence.tracks.flatMap(\.clips).first{$0.id==marker.clipID}?.assetID}
    private func label(_ marker:Marker)->String{
        let name=marker.name.isEmpty ? "Marker":marker.name
        let file=store.document.assets.first{$0.id==assetID(for:marker)}?.url.lastPathComponent ?? "Missing"
        return "\(name) · \(String(format:"%.3f s",marker.time.seconds)) · \(file)\(marker.duration > .zero ? " · Start":"")"
    }
    private func picker(_ title:String,selection:Binding<UUID?>)->some View{
        Picker(title,selection:selection){
            Text("Choose marker").tag(Optional<UUID>.none)
            ForEach(markers){marker in Text(label(marker)).tag(Optional(marker.id))}
        }.accessibilityLabel("\(title) clip marker")
    }
}
