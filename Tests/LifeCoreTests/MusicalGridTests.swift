import Foundation
import Testing
@testable import LifeCore
private func mt(_ n: Int64, _ d: Int64 = 1) -> RationalTime { .init(value:n,timescale:d) }
@Test func manualGridUsesExactBeatTripletSwingAndBarPositions() throws {
    let grid=MusicalGrid(bpm:120,beatsPerBar:4,subdivision:3)
    let points=grid.divisions(from:.zero,to:mt(2))
    #expect(points[1].time == mt(1,6))
    #expect(points[3].time == mt(1,2))
    #expect(points.last?.isBar == true)
    #expect(grid.nearestDivision(to:mt(49,100))?.time == mt(1,2))
    let swung=MusicalGrid(bpm:120,subdivision:2,swing:1)
    #expect(swung.divisions(from:.zero,to:mt(1,2))[1].time == mt(1,3))
    let eighth=MusicalGrid(bpm:120,subdivision:1,beatUnit:8)
    #expect(eighth.divisions(from:.zero,to:mt(1,2)).map(\.time) == [.zero,mt(1,4),mt(1,2)])
    #expect(grid.divisions(from:.zero,to:mt(3600),maximumCount:20).count == 20)
}
@Test func manualAnchorsRepresentTempoChangesAndLiveDriftContinuously() {
    let grid=MusicalGrid(bpm:120,anchors:[BeatAnchor(time:.zero,beatIndex:0),BeatAnchor(time:mt(2),beatIndex:4),BeatAnchor(time:mt(5),beatIndex:8)])
    let divisions=grid.divisions(from:.zero,to:mt(6))
    #expect(divisions.first(where: { $0.beatIndex == 3 })?.time == mt(3,2))
    #expect(divisions.first(where: { $0.beatIndex == 5 })?.time == mt(11,4))
    #expect(divisions.first(where: { $0.beatIndex == 8 })?.time == mt(5))
    #expect(divisions.first(where: { $0.beatIndex == 9 })?.time == mt(11,2))
    #expect(grid.nearestDivision(to:mt(279,100))?.beatIndex == 5)
}
@MainActor @Test func shiftingGridOnlyMovesAnnotationsAndPersistsUndo() throws {
    let clip=Clip(duration:mt(10)), grid=MusicalGrid(anchors:[BeatAnchor(time:mt(1),beatIndex:0),BeatAnchor(time:mt(3),beatIndex:4)])
    let doc=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Music",kind:.audio,clips:[clip])],musicalGrid:grid)), editor=ProjectEditor(document:doc)
    var next=doc; next.sequence.musicalGrid=try grid.moved(by:mt(1,48000))
    try editor.perform(.replace(next))
    #expect(editor.document.sequence.tracks == doc.sequence.tracks)
    #expect(editor.document.sequence.musicalGrid?.anchors?.first?.time == mt(48001,48000))
    #expect(try ProjectDocument.decode(editor.document.encoded()) == next)
    editor.undo(); #expect(editor.document == doc)
}
@Test func gridRejectsNonmonotonicAnchorsAndOldFieldsDecode() throws {
    var grid=MusicalGrid(anchors:[BeatAnchor(time:mt(2),beatIndex:4),BeatAnchor(time:mt(1),beatIndex:8)])
    #expect(!grid.isValid)
    grid=MusicalGrid(anchors:[BeatAnchor(time:mt(1),beatIndex:4),BeatAnchor(time:mt(2),beatIndex:3)])
    #expect(!grid.isValid)
    #expect(!MusicalGrid(swing:.nan).isValid)
    #expect(!MusicalGrid(beatUnit:7).isValid)
    let old=Data(#"{"bpm":120,"offset":{"value":0,"timescale":1},"beatsPerBar":4,"subdivision":1}"#.utf8)
    let decoded=try JSONDecoder().decode(MusicalGrid.self,from:old)
    #expect(decoded.anchors == nil); #expect(decoded.swing == nil); #expect(decoded.beatUnit == nil)
}
@MainActor @Test func clipSourceMarkersMapAcrossTrimSpeedAndSplitRanges() throws {
    let asset=MediaAsset(url:URL(fileURLWithPath:"/tmp/take.mov"),kind:.video,duration:mt(30))
    let clip=Clip(assetID:asset.id,start:mt(3),duration:mt(10),sourceStart:mt(4),speed:2)
    let point=Marker(time:mt(10),name:"Verse",note:"Keep this note",clipID:clip.id), hidden=Marker(time:mt(2),clipID:clip.id), range=Marker(time:mt(10),duration:mt(8),name:"Chorus",clipID:clip.id)
    let doc=ProjectDocument(sequence:Sequence(tracks:[Track(name:"V",kind:.video,clips:[clip])],markers:[point,hidden,range]),assets:[asset]), editor=ProjectEditor(document:doc)
    #expect(MarkerResolver.sequenceRange(point,in:doc)?.start == mt(6))
    #expect(MarkerResolver.sequenceRange(hidden,in:doc) == nil)
    #expect(MarkerResolver.sequenceRange(range,in:doc)?.duration == mt(4))
    try editor.perform(.trim(clipID:clip.id,start:mt(5),end:mt(13)))
    #expect(MarkerResolver.sequenceRange(point,in:editor.document)?.start == mt(6))
    editor.undo()
    try editor.perform(.split(clipID:clip.id,at:mt(8))) // source boundary14 bisects source marker range10...18.
    let pieces=editor.document.sequence.markers.filter { $0.name == "Chorus" }.compactMap { MarkerResolver.sequenceRange($0,in:editor.document) }.sorted { $0.start < $1.start }
    #expect(pieces.count == 2); #expect(pieces.map(\.duration) == [mt(2),mt(2)])
    #expect(pieces[0].end == pieces[1].start)
    editor.undo(); #expect(editor.document == doc)
    try editor.perform(.convertMarkerToTitle(id:point.id))
    #expect(editor.document.sequence.markers == doc.sequence.markers)
    #expect(editor.document.sequence.tracks.last?.clips.first?.title?.text == "Verse")
    #expect(editor.document.sequence.tracks.last?.clips.first?.start == mt(6))
    editor.undo(); #expect(editor.document == doc)
}
