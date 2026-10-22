import SwiftUI
import LifeCore
struct PlacementPreviewControls:View {
    @ObservedObject var store:EditorStore
    var body:some View{
        if let proposal=store.placementProposal{
            HStack(spacing:8){
                Text(store.placementTitle).font(.caption.weight(.medium))
                Text("\(proposal.affectedTrackIDs.count)").monospacedDigit().font(.caption).accessibilityLabel("Affected tracks").help("Affected tracks")
                Button("Cancel",action:store.cancelPlacement).help("Cancel placement · Esc")
                Button("Apply",action:store.commitPlacement).buttonStyle(.borderedProminent).help("Apply placement")
            }.fixedSize()
        }
    }
}
