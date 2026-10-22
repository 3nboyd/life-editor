import SwiftUI
import LifeCore

struct EditControls:View {
    @ObservedObject var store:EditorStore
    @State private var expanded=false
    @State private var ripple=false
    private var clip:Clip?{store.selectedClip}
    private var track:Track?{store.document.sequence.tracks.first{$0.clips.contains{$0.id==store.selection}}}
    var body:some View{
        if let clip,let track{
            DisclosureGroup("Trim",isExpanded:$expanded){
                VStack(spacing:10){
                    Toggle("Ripple",isOn:$ripple).toggleStyle(.button).help("Preview a ripple trim on linked and grouped tracks")
                    HStack{Text("In");TextField("Seconds",value:Binding(get:{self.clip?.start.seconds ?? clip.start.seconds},set:{value in trim(start:value,end:clip.end.seconds,clip:clip,audio:track.kind == .audio)}),format:.number.precision(.fractionLength(5))).textFieldStyle(.roundedBorder).accessibilityLabel("Trim in seconds")}
                    HStack{Text("Out");TextField("Seconds",value:Binding(get:{self.clip?.end.seconds ?? clip.end.seconds},set:{value in trim(start:clip.start.seconds,end:value,clip:clip,audio:track.kind == .audio)}),format:.number.precision(.fractionLength(5))).textFieldStyle(.roundedBorder).accessibilityLabel("Trim out seconds")}
                    SourceExtensionControls(store:store,clip:clip)
                    if clip.assetID != nil,clip.freezeFrame == nil{
                        HStack{Text("Source");TextField("Seconds",value:Binding(get:{self.clip?.sourceStart.seconds ?? clip.sourceStart.seconds},set:{value in
                            guard value.isFinite,(0...86400).contains(value) else{return}
                            let delta=RationalTime(value:Int64(((value-clip.sourceStart.seconds)*48000).rounded()),timescale:48000)
                            store.apply(.slip(clipID:clip.id,by:delta))
                        }),format:.number.precision(.fractionLength(5))).textFieldStyle(.roundedBorder).accessibilityLabel("Slip source start seconds")}
                    }
                    if clip.freezeFrame == nil,let right=track.clips.first(where:{$0.id != clip.id && $0.start==clip.end && $0.freezeFrame == nil}){
                        HStack{Text("Roll");TextField("Seconds",value:Binding(get:{self.clip?.end.seconds ?? clip.end.seconds},set:{value in
                            guard value.isFinite,(0...86400).contains(value) else{return}
                            store.apply(.roll(leftClipID:clip.id,rightClipID:right.id,to:store.time(value,audio:track.kind == .audio)))
                        }),format:.number.precision(.fractionLength(5))).textFieldStyle(.roundedBorder).accessibilityLabel("Roll shared boundary seconds")}
                    }
                }.padding(.top,8).disabled(track.isLocked)
            }
        }
    }
    private func trim(start:Double,end:Double,clip:Clip,audio:Bool){
        guard start.isFinite,end.isFinite,(0...86400).contains(start),(0...86400).contains(end),end>start else{return}
        if ripple{store.previewPlacement(.rippleTrim(clipID:clip.id,start:store.time(start,audio:audio),end:store.time(end,audio:audio)),title:"Ripple Trim")}else{store.apply(.trim(clipID:clip.id,start:store.time(start,audio:audio),end:store.time(end,audio:audio)))}
    }
}
