import SwiftUI
import LifeCore

struct MarkerControls:View {
    @ObservedObject var store:EditorStore
    @State private var selected:UUID?
    private var marker:Marker?{store.document.sequence.markers.first{$0.id==selected}}
    var body:some View{
        ScrollView{VStack(alignment:.leading,spacing:12){
            HStack{
                Button{store.addMarker();selected=store.document.sequence.markers.last?.id}label:{Image(systemName:"plus")}.help("Add marker · M").accessibilityLabel("Add marker")
                Button{store.addRangeMarker();selected=store.document.sequence.markers.last?.id}label:{Image(systemName:"arrow.left.and.right")}.help("Add range marker").accessibilityLabel("Add range marker")
                Spacer()
            }
            ForEach(store.document.sequence.markers){item in
                Button{selected=item.id;if let range=MarkerResolver.sequenceRange(item,in:store.document){store.seek(range.start.seconds)}}label:{
                    HStack{Image(systemName:item.duration == .zero ? "bookmark":"arrow.left.and.right");Text(item.name.isEmpty ? "Marker":item.name).lineLimit(1);Spacer();if selected==item.id{Image(systemName:"checkmark")}}
                }.buttonStyle(.plain).help("Go to marker").accessibilityLabel(item.name.isEmpty ? "Marker":item.name)
            }
            if let marker{
                Divider()
                TextField("Name",text:Binding(get:{self.marker?.name ?? ""},set:{value in store.editMarker(marker.id){$0.name=value}})).textFieldStyle(.roundedBorder).accessibilityLabel("Marker name")
                TextField("Note",text:Binding(get:{self.marker?.note ?? ""},set:{value in store.editMarker(marker.id){$0.note=value}}),axis:.vertical).lineLimit(3...8).textFieldStyle(.roundedBorder).accessibilityLabel("Marker note")
                if let range=MarkerResolver.sequenceRange(marker,in:store.document){
                    HStack{Text("Start");TextField("Seconds",value:Binding(get:{MarkerResolver.sequenceRange(self.marker ?? marker,in:store.document)?.start.seconds ?? 0},set:{store.setMarkerTiming(marker.id,start:$0,duration:nil)}),format:.number.precision(.fractionLength(4))).textFieldStyle(.roundedBorder).accessibilityLabel("Marker start seconds")}
                    HStack{Text("Length");TextField("Seconds",value:Binding(get:{MarkerResolver.sequenceRange(self.marker ?? marker,in:store.document)?.duration.seconds ?? range.duration.seconds},set:{store.setMarkerTiming(marker.id,start:nil,duration:$0)}),format:.number.precision(.fractionLength(4))).textFieldStyle(.roundedBorder).accessibilityLabel("Marker duration seconds")}
                }else{Label("Outside clip",systemImage:"eye.slash").foregroundStyle(.secondary)}
                Toggle("Follow clip",isOn:Binding(get:{self.marker?.clipID != nil},set:{store.anchorMarker(marker.id,toSelected:$0)})).disabled(marker.clipID==nil && store.selectedClip==nil)
                SharedColorPicker(label:"Color",color:Binding(get:{self.marker?.color ?? RGBAColor(red:1,green:0.6,blue:0.2,alpha:1)},set:{value in store.editMarker(marker.id){$0.color=value}}),store:store)
                HStack{Button("Title"){store.apply(.convertMarkerToTitle(id:marker.id))}.help("Convert marker to a visible title");Spacer();Button{store.removeMarker(marker.id);selected=nil}label:{Image(systemName:"trash")}.help("Delete marker").accessibilityLabel("Delete marker")}
            }
        }}
    }
}

extension EditorStore {
    func addRangeMarker(){var next=document;next.sequence.markers.append(.init(time:time(playhead),duration:.init(value:2,timescale:1),name:"Range"));replace(next)}
    func editMarker(_ id:UUID,_ update:(inout Marker)->Void){
        var next=document;guard let index=next.sequence.markers.firstIndex(where:{$0.id==id}) else{return}
        update(&next.sequence.markers[index]);replace(next)
    }
    func removeMarker(_ id:UUID){var next=document;next.sequence.markers.removeAll{$0.id==id};replace(next)}
    func setMarkerTiming(_ id:UUID,start:Double?,duration:Double?){
        guard [start,duration].compactMap({$0}).allSatisfy({$0.isFinite && (0...86400).contains($0)}) else{return}
        guard let marker=document.sequence.markers.first(where:{$0.id==id}),let current=MarkerResolver.sequenceRange(marker,in:document) else{return}
        let sequenceStart=time(start ?? current.start.seconds,audio:true),sequenceDuration=time(duration ?? current.duration.seconds,audio:true)
        if let clipID=marker.clipID,let clip=document.sequence.tracks.flatMap(\.clips).first(where:{$0.id==clipID}){
            guard sequenceStart>=clip.start,sequenceStart<clip.end,sequenceStart+sequenceDuration<=clip.end else{error="Keep this marker inside its clip.";return}
            do{let source=try clip.checkedSourceTime(at:sequenceStart),length=try sequenceDuration.checkedScaled(by:Int64((clip.speed*1_000_000).rounded()),over:1_000_000);editMarker(id){$0.time=source;$0.duration=length}}catch{self.error=Self.message(error)}
        }else{editMarker(id){$0.time=sequenceStart;$0.duration=sequenceDuration}}
    }
    func anchorMarker(_ id:UUID,toSelected:Bool){
        guard let marker=document.sequence.markers.first(where:{$0.id==id}),let range=MarkerResolver.sequenceRange(marker,in:document) else{return}
        if toSelected{
            guard let clip=selectedClip,range.start>=clip.start,range.end<=clip.end else{error="Select a clip containing this marker.";return}
            do{let source=try clip.checkedSourceTime(at:range.start),length=try range.duration.checkedScaled(by:Int64((clip.speed*1_000_000).rounded()),over:1_000_000);editMarker(id){$0.clipID=clip.id;$0.time=source;$0.duration=length}}catch{self.error=Self.message(error)}
        }else{editMarker(id){$0.clipID=nil;$0.time=range.start;$0.duration=range.duration}}
    }
}
