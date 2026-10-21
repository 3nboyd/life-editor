import SwiftUI
import LifeCore

struct MusicalGridControls:View {
    @ObservedObject var store:EditorStore
    @State private var anchorBeat=0
    var body:some View{
        VStack(alignment:.leading,spacing:12){
            Picker("Beat unit",selection:Binding(get:{store.document.sequence.musicalGrid?.beatUnit ?? 4},set:{value in store.setGrid{$0.beatUnit=value}})){
                Text("¼").tag(4);Text("⅛").tag(8);Text("½").tag(2)
            }.pickerStyle(.segmented)
            HStack{Text("Swing");Slider(value:Binding(get:{store.document.sequence.musicalGrid?.swing ?? 0},set:{value in store.setGrid{$0.swing=value}}),in:0...1,onEditingChanged:{active in if active{store.beginGesture()}else{store.endGesture()}}).accessibilityLabel("Grid swing")}
            HStack{
                Text("Beat");TextField("Beat",value:$anchorBeat,format:.number).textFieldStyle(.roundedBorder).accessibilityLabel("Anchor beat number")
                Button{guard (-1_000_000...1_000_000).contains(anchorBeat) else{return};store.setGrid{grid in
                    var anchors=grid.anchors ?? [];anchors.removeAll{$0.beatIndex==Int64(anchorBeat)}
                    anchors.append(.init(time:store.time(store.playhead,audio:true),beatIndex:Int64(anchorBeat)))
                    grid.anchors=anchors.sorted{$0.beatIndex<$1.beatIndex}
                }}label:{Image(systemName:"plus.diamond")}.help("Anchor beat at playhead").accessibilityLabel("Anchor beat at playhead")
            }
            ForEach(store.document.sequence.musicalGrid?.anchors ?? []){anchor in
                HStack{
                    Button("\(anchor.beatIndex)"){store.seek(anchor.time.seconds)}.help("Go to beat anchor")
                    TextField("Seconds",value:Binding(get:{store.document.sequence.musicalGrid?.anchors?.first(where:{$0.id==anchor.id})?.time.seconds ?? 0},set:{value in guard value.isFinite,(0...86400).contains(value) else{return};store.setGrid{grid in if let i=grid.anchors?.firstIndex(where:{$0.id==anchor.id}){grid.anchors?[i].time=store.time(value,audio:true)}}}),format:.number.precision(.fractionLength(3))).textFieldStyle(.roundedBorder).accessibilityLabel("Beat \(anchor.beatIndex) anchor seconds")
                    Button{store.setGrid{$0.anchors?.removeAll{$0.id==anchor.id}}}label:{Image(systemName:"minus.circle")}.help("Remove beat anchor").accessibilityLabel("Remove beat anchor")
                }
            }
        }
    }
}
