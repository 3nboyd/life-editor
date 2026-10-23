import SwiftUI
import LifeCore
import LifeMedia

struct CamcorderDateControls:View {
    @ObservedObject var store:EditorStore
    let effectID:UUID
    let asset:MediaAsset
    @State private var open=false
    @State private var draft=""
    @State private var invalid=false
    @State private var candidate:CamcorderDateOverlay?
    private var overlay:CamcorderDateOverlay?{store.selectedClip?.effects?.first{$0.id==effectID}?.camcorderDate}
    private var baseline:String{
        let current=store.document.assets.first{$0.id==store.selectedClip?.assetID}
        return "\(store.selection?.uuidString ?? "")|\(effectID)|\(current?.id.uuidString ?? "")|\(current?.url.absoluteString ?? "")"
    }
    var body:some View {
        Button{draft=overlay?.entryText ?? "";invalid=false;open.toggle()}label:{Image(systemName:"calendar.badge.clock").frame(width:24,height:24)}
            .help("Camcorder date").accessibilityLabel("Camcorder date").popover(isPresented:$open){
                VStack(alignment:.leading,spacing:12){
                    Toggle("Date",isOn:Binding(get:{overlay?.enabled ?? false},set:{enabled in update{value in value.enabled=enabled}})).disabled(overlay==nil)
                    HStack{
                        TextField("YYYY-MM-DDTHH:MM:SS±HH:MM",text:$draft).textFieldStyle(.roundedBorder).accessibilityLabel("Source start date with timezone").onSubmit{commitDraft()}
                        Button{commitDraft()}label:{Image(systemName:"checkmark").frame(width:24,height:24)}.help("Apply date").accessibilityLabel("Apply date").disabled(CamcorderDateOverlay.parse(draft)==nil)
                    }
                    if invalid{Text("Use an ISO date with timezone.").font(.caption).foregroundStyle(.red)}
                    if let candidate{Button("Metadata"){applyDate(candidate);draft=candidate.entryText;invalid=false}.help("Use content creation metadata; verify the date")}
                    if overlay?.origin == .recorded{Text("Metadata").font(.caption).foregroundStyle(.secondary)}
                    Picker("Format",selection:Binding(get:{overlay?.format ?? .dateTime},set:{format in update{$0.format=format}})){
                        Text("Date").tag(CamcorderDateFormat.date);Text("Time").tag(CamcorderDateFormat.time);Text("Both").tag(CamcorderDateFormat.dateTime)
                    }.pickerStyle(.segmented).disabled(overlay==nil)
                    Picker("Corner",selection:Binding(get:{overlay?.corner ?? .bottomRight},set:{corner in update{$0.corner=corner}})){
                        Text("↖").tag(CamcorderDateCorner.topLeft).accessibilityLabel("Top left");Text("↗").tag(CamcorderDateCorner.topRight).accessibilityLabel("Top right");Text("↙").tag(CamcorderDateCorner.bottomLeft).accessibilityLabel("Bottom left");Text("↘").tag(CamcorderDateCorner.bottomRight).accessibilityLabel("Bottom right")
                    }.pickerStyle(.segmented).disabled(overlay==nil)
                }.padding(16).frame(width:350)
            }.onChange(of:overlay){previous,current in
                guard previous?.sourceZeroUnixSeconds != current?.sourceZeroUnixSeconds || previous?.utcOffsetSeconds != current?.utcOffsetSeconds else{return}
                let parsed=CamcorderDateOverlay.parse(draft)
                let matches=draft == (previous?.entryText ?? "") || (parsed != nil && previous != nil && parsed?.sourceZeroUnixSeconds==previous?.sourceZeroUnixSeconds && parsed?.utcOffsetSeconds==previous?.utcOffsetSeconds)
                if matches{draft=current?.entryText ?? "";invalid=false}
            }.task(id:baseline){
                let expected=baseline;candidate=nil
                do{let value=try await CamcorderRecordingDate.candidate(for:asset);guard !Task.isCancelled,expected==baseline else{return};candidate=value}catch{if expected==baseline,!Task.isCancelled{candidate=nil}}
            }
    }
    private func commitDraft(){
        guard let value=CamcorderDateOverlay.parse(draft) else{invalid=true;return}
        applyDate(value);invalid=false
    }
    func applyDate(_ date:CamcorderDateOverlay){
        var value=date
        if let old=overlay{value.format=old.format;value.corner=old.corner;value.enabled=old.enabled}
        apply(value)
    }
    private func update(_ change:(inout CamcorderDateOverlay)->Void){guard var value=overlay else{return};change(&value);apply(value)}
    private func apply(_ value:CamcorderDateOverlay){
        store.editSelected{clip in guard let index=clip.effects?.firstIndex(where:{$0.id==effectID}) else{return};clip.effects?[index].camcorderDate=value}
    }
}
