import SwiftUI
import LifeCore

struct CameraDriftControls:View {
    @Binding var candidate:CameraSyncCandidate
    @State private var open=false
    var body:some View {
        if let correction=candidate.correction {
            Button{open.toggle()}label:{Image(systemName:candidate.correctDrift ? "clock.badge.checkmark":"clock").frame(width:24,height:24)}.help("Review clock drift").accessibilityLabel("Review clock drift").accessibilityValue(candidate.correctDrift ? "Correction selected":"Correction off").popover(isPresented:$open){
                VStack(alignment:.leading,spacing:10){
                    Toggle("Correct clock",isOn:$candidate.correctDrift)
                    HStack{Text("Rate");Spacer();Text(String(format:"%.6f×",correction.speed)).monospacedDigit()}
                    HStack{Text("Uncertainty");Spacer();Text(String(format:"±%.0f ms",correction.uncertaintySeconds*1000)).monospacedDigit()}
                    Grid(horizontalSpacing:12,verticalSpacing:6){
                        GridRow{Text("");Text("Source");Text("Master")}
                        ForEach(Array([correction.early,correction.middle,correction.late].enumerated()),id:\.offset){index,anchor in
                            GridRow{Text(["Early","Middle","Late"][index]);Text(String(format:"%.3f",anchor.sourceSeconds));Text(String(format:"%.3f",anchor.referenceSeconds))}
                        }
                    }.font(.caption.monospacedDigit())
                }.padding(16).frame(width:280)
            }
        }
    }
}
