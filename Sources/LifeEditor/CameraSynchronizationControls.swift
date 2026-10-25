import SwiftUI

struct CameraSynchronizationControls:View {
    @ObservedObject var store:EditorStore
    var body:some View {
        VStack(alignment:.leading,spacing:8){
            HStack{
                Picker("Sync",selection:$store.syncMethod){Text("Waveform").tag(CameraSyncMethod.waveform);Text("Timecode").tag(CameraSyncMethod.timecode)}.pickerStyle(.segmented).disabled(store.synchronizing)
                if store.synchronizing{ProgressView().controlSize(.small);Button{store.cancelSynchronization()}label:{Image(systemName:"xmark")}.help("Cancel synchronization").accessibilityLabel("Cancel synchronization")}
                else{Button{store.synchronizeCameras()}label:{Image(systemName:"arrow.triangle.2.circlepath")}.help("Analyze synchronization").accessibilityLabel("Analyze synchronization")}
            }
            HStack{Spacer();Button{store.prepareManualSynchronization()}label:{Image(systemName:"hand.draw").frame(width:24,height:24)}.help("Review manual camera offsets").accessibilityLabel("Review manual camera offsets").disabled(store.synchronizing)}
            MarkerSynchronizationControls(store:store)
            if let reference=store.syncReferenceID,let asset=store.document.assets.first(where:{$0.id==reference}){
                Label(asset.url.lastPathComponent,systemImage:"pin.fill").font(.caption).lineLimit(1).help("Synchronization reference")
            }
            ForEach($store.syncCandidates){$candidate in
                VStack(alignment:.leading,spacing:3){
                    HStack{
                        Text(store.document.assets.first(where:{$0.id==candidate.assetID})?.url.lastPathComponent ?? "Camera").lineLimit(1)
                        TextField("Offset",value:$candidate.offset,format:.number.precision(.fractionLength(3))).textFieldStyle(.roundedBorder).frame(width:66).accessibilityLabel("Camera offset in seconds")
                        CameraDriftControls(candidate:$candidate)
                        Text(String(format:"%.0f%%",candidate.confidence*100)).font(.caption.monospacedDigit()).foregroundStyle(candidate.confidence<0.6 ? .orange:.secondary)
                    }
                    if let note=candidate.note{Label(note,systemImage:candidate.confidence == 0 ? "pencil":"exclamationmark.triangle").font(.caption).foregroundStyle(.orange)}
                    if let drift=candidate.drift{Text(String(format:"Drift %+.0f ms",drift*1000)).font(.caption).foregroundStyle(.orange)}
                }
            }
            if !store.syncCandidates.isEmpty {
                HStack{Button("Preview"){store.previewSynchronization()};Button("Apply"){store.applySynchronization()};Button("Cancel"){store.cancelSynchronization()}}
            }
        }
    }
}
