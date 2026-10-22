import Foundation
import LifeCore

struct TimelineTrackRow:Equatable {
    let trackID:UUID;let index:Int;let top:Double;let height:Double
    var bottom:Double { top+height }
}
/// Window layout preferences, separate from the undoable editing document.
@MainActor final class TimelineLayout {
    private(set) var projectID:UUID
    private(set) var revision=0
    private let defaults:UserDefaults
    private var heights:[String:Double]=[:]
    private var cachedIDs:[UUID]=[]
    private var cachedRows:[TimelineTrackRow]=[]
    private var cachedRevision = -1
    init(projectID:UUID,defaults:UserDefaults = .standard){self.projectID=projectID;self.defaults=defaults;load()}
    private var key:String { "LifeEditor.timeline.heights.v1."+projectID.uuidString }
    func useProject(_ id:UUID){guard id != projectID else{return};projectID=id;load();revision+=1}
    private func load(){heights=(defaults.dictionary(forKey:key) as? [String:Double] ?? [:]).filter{$0.value.isFinite && (56...240).contains($0.value)}}
    func height(for id:UUID)->Double { heights[id.uuidString] ?? 76 }
    @discardableResult func setHeight(_ value:Double,for id:UUID)->Bool {
        guard value.isFinite else{return false}
        let bounded=min(240,max(56,value));guard height(for:id) != bounded else{return false}
        heights[id.uuidString]=bounded;revision+=1;defaults.set(heights,forKey:key);return true
    }
    func rows(for tracks:[Track])->[TimelineTrackRow] {
        let ids=tracks.map(\.id)
        if cachedRevision==revision,cachedIDs==ids{return cachedRows}
        var top=32.0
        cachedRows=tracks.enumerated().map{index,track in let row=TimelineTrackRow(trackID:track.id,index:index,top:top,height:height(for:track.id));top=row.bottom;return row}
        cachedIDs=ids;cachedRevision=revision;return cachedRows
    }
    func row(at y:Double,tracks:[Track])->Int? { rows(for:tracks).first{$0.top<=y && y<$0.bottom}?.index }
    func totalHeight(for tracks:[Track])->Double { rows(for:tracks).last?.bottom ?? 32 }
}
