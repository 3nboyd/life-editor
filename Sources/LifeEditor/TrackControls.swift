import SwiftUI
import LifeCore

struct TrackControls:View {
    @ObservedObject var store:EditorStore
    @State private var expanded=false
    private var track:Track?{store.document.sequence.tracks.first{$0.clips.contains{$0.id==store.selection}}}
    var body:some View{
        if let track,let index=store.document.sequence.tracks.firstIndex(where:{$0.id==track.id}){
            DisclosureGroup("Track",isExpanded:$expanded){
                VStack(spacing:10){
                    TextField("Name",text:Binding(get:{self.track?.name ?? track.name},set:{store.apply(.renameTrack(trackID:track.id,name:$0))})).textFieldStyle(.roundedBorder).accessibilityLabel("Track name").disabled(track.isLocked)
                    HStack{
                        Button{store.apply(.reorderTrack(trackID:track.id,to:index+1))}label:{Image(systemName:"arrow.up")}.disabled(index==store.document.sequence.tracks.count-1 || track.isLocked).help("Move track up").accessibilityLabel("Move track up")
                        Button{store.apply(.reorderTrack(trackID:track.id,to:index-1))}label:{Image(systemName:"arrow.down")}.disabled(index==0 || track.isLocked).help("Move track down").accessibilityLabel("Move track down")
                        Spacer()
                        Button{store.toggleTrack(track.id,property:"mute")}label:{Image(systemName:track.isMuted ? "speaker.slash.fill":"speaker.wave.2")}.help("Mute track").accessibilityLabel(track.isMuted ? "Unmute track":"Mute track")
                        Button{store.toggleTrack(track.id,property:"hide")}label:{Image(systemName:track.isHidden ? "eye.slash":"eye")}.help("Hide track").accessibilityLabel(track.isHidden ? "Show track":"Hide track")
                        Button{store.toggleTrack(track.id,property:"lock")}label:{Image(systemName:track.isLocked ? "lock.fill":"lock.open")}.help("Lock track").accessibilityLabel(track.isLocked ? "Unlock track":"Lock track")
                    }
                    Button("Delete Track",role:.destructive){
                        let alert=NSAlert();alert.messageText="Delete \(track.name)?";alert.informativeText="This removes the track and its clips.";alert.addButton(withTitle:"Delete");alert.addButton(withTitle:"Cancel")
                        if alert.runModal() == .alertFirstButtonReturn{store.apply(.removeTrack(trackID:track.id))}
                    }.disabled(track.isLocked)
                }.padding(.top,8)
            }
        }
    }
}
