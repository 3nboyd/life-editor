import Testing
import AppKit
import LifeCore
@testable import LifeEditor
private func tl(_ n:Int64,_ d:Int64=1)->RationalTime { .init(value:n,timescale:d) }
@MainActor @Test func timelineSnapsToAnchoredMusicButPrioritizesExplicitTargets() throws {
    let store=EditorStore();store.gridMode = .beats; store.pixelsPerSecond=100;store.playhead=20
    store.document=ProjectDocument(sequence:Sequence(musicalGrid:MusicalGrid(bpm:120,anchors:[BeatAnchor(time:.zero,beatIndex:0),BeatAnchor(time:tl(2),beatIndex:4),BeatAnchor(time:tl(5),beatIndex:8)])))
    let canvas=TimelineCanvas(store:store)
    let beat=try #require(canvas.snappedTime(2.77))
    #expect(abs(beat.time-2.75)<0.000001);#expect(beat.label == "Beat")
    let clip=Clip(start:tl(281,100),duration:tl(1))
    store.document.sequence.tracks=[Track(name:"Audio",kind:.audio,clips:[clip])]
    let explicit=try #require(canvas.snappedTime(2.77))
    #expect(abs(explicit.time-2.81)<0.000001);#expect(explicit.label == "Clip")
    store.gridVisible=false
    #expect(canvas.snappedTime(2.77,excluding:[clip.id])?.label == "Beat")
    store.pixelsPerSecond=1000
    #expect(canvas.snappedTime(2.77,excluding:[clip.id]) == nil) // Same seconds, outside eight screen pixels.
}
@MainActor @Test func timelineMarkerSnapsUseSourceMappingAndRangeEnds() throws {
    let store=EditorStore();store.pixelsPerSecond=100;store.playhead=20
    let clip=Clip(start:tl(3),duration:tl(10),sourceStart:tl(4),speed:2)
    let marker=Marker(time:tl(10),duration:tl(4),name:"Verse",clipID:clip.id)
    store.document=ProjectDocument(sequence:Sequence(tracks:[Track(name:"V",kind:.video,clips:[clip])],markers:[marker]))
    let canvas=TimelineCanvas(store:store)
    #expect(canvas.snappedTime(6.02)?.label == "Verse")
    #expect(canvas.snappedTime(6.02)?.time == 6)
    #expect(canvas.snappedTime(8.02)?.time == 8)
}
@MainActor @Test func timelineAccessibilityDoesNotRebuildForPlaybackTicks() {
    _ = NSApplication.shared
    let store=EditorStore(), clip=Clip(duration:tl(4))
    store.document=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Video",kind:.video,clips:[clip])]))
    let canvas=TimelineCanvas(store:store);canvas.frame=NSRect(x:0,y:0,width:1200,height:300)
    canvas.refreshAccessibility();let baseline=canvas.accessibilityRebuildCount
    for i in 0..<30 { store.playhead=Double(i)/30;canvas.refreshAccessibility() }
    #expect(canvas.accessibilityRebuildCount == baseline)
    store.selectedIDs=[clip.id];canvas.refreshAccessibility()
    #expect(canvas.accessibilityRebuildCount == baseline+1)
    canvas.frame.size.width=1400;canvas.refreshAccessibility()
    #expect(canvas.accessibilityRebuildCount == baseline+2)
    canvas.setBoundsOrigin(NSPoint(x:40,y:0));canvas.refreshAccessibility()
    #expect(canvas.accessibilityRebuildCount == baseline+3)
}
