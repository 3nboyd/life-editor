import SwiftUI
import LifeCore
import LifeMedia

struct SourceExtensionControls:View {
    @ObservedObject var store:EditorStore
    let clip:Clip
    @State private var seconds=1.0
    @State private var preparing=false
    @State private var job:Task<Void,Never>?
    private var asset:MediaAsset?{store.document.assets.first{$0.id==clip.assetID}}
    private var atBoundary:Bool{
        guard clip.freezeFrame==nil,let asset,asset.kind == .video,
              let end=try? clip.checkedSourceTime(at:clip.end) else{return false}
        if store.document.sequence.multicamGroups.contains(where:{$0.angleAssetIDs.contains(asset.id) || $0.masterAudioAssetID==asset.id || ($0.audioAssetIDs ?? []).contains(asset.id)}){return false}
        let remaining=asset.duration.seconds-end.seconds
        return remaining>=0 && remaining<store.document.sequence.settings.frameRate.frameDuration.seconds*clip.speed
    }
    var body:some View{
        if atBoundary{
            HStack(spacing:8){
                TextField("Seconds",value:$seconds,format:.number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder).frame(width:60).accessibilityLabel("Freeze extension seconds")
                Text("s").font(.caption).foregroundStyle(.secondary)
                Button(action:extend){Label("Freeze",systemImage:"snowflake")}
                    .help("Extend with the last source frame")
                    .disabled(preparing || !seconds.isFinite || seconds<=0 || seconds>86400 || store.placementProposal != nil)
                if preparing{ProgressView().controlSize(.small)}
            }.onDisappear{job?.cancel()}
        }
    }
    private func extend(){
        guard let asset else{return}
        let baseline=store.document,length=store.time(seconds)
        preparing=true
        job=Task{@MainActor in
            defer{preparing=false;job=nil}
            do{
                let frame=try await MediaPipeline().lastVideoFrameTime(asset:asset)
                try Task.checkCancellation()
                guard store.document==baseline,store.selection==clip.id else{
                    store.error="The project changed. Extend this clip again.";return
                }
                store.apply(.extendFreezeFrame(clipID:clip.id,duration:length,sourceFrameTime:frame))
            }catch is CancellationError{}catch{store.error=error.localizedDescription}
        }
    }
}
