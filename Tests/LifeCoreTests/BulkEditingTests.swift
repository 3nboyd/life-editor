import Foundation
import Testing
@testable import LifeCore
private func bt(_ n: Int64, _ scale: Int64 = 1) -> RationalTime { .init(value:n,timescale:scale) }
@MainActor @Test func bulkMoveExpandsLinksOnceAndRetainsSamplePrecision() throws {
    let link=UUID(), v=Clip(start:bt(1),duration:bt(2),linkID:link), a=Clip(start:bt(1),duration:bt(2),linkID:link)
    let doc=ProjectDocument(sequence:.init(tracks:[Track(name:"V",kind:.video,clips:[v]),Track(name:"A",kind:.audio,clips:[a])]))
    let editor=ProjectEditor(document:doc)
    try editor.perform(.moveMany(clipIDs:[v.id,a.id],delta:bt(1)))
    #expect(editor.document.sequence.tracks.flatMap(\.clips).allSatisfy { $0.start == bt(2) })
    editor.undo(); #expect(editor.document == doc)
    try editor.perform(.moveMany(clipIDs:[a.id],delta:bt(1,48000)))
    #expect(editor.document == doc) // Linked video forces a shared frame delta.
    try editor.perform(.detach(clipIDs:[a.id]))
    #expect(editor.document.sequence.tracks.flatMap(\.clips).allSatisfy { $0.linkID == nil })
    try editor.perform(.moveMany(clipIDs:[a.id],delta:bt(1,48000)))
    #expect(editor.document.sequence.tracks[1].clips[0].start == bt(48001,48000))
    #expect(editor.document.sequence.tracks[0].clips[0].start == bt(1))
}
@MainActor @Test func bulkLockedAndOverlapFailuresAreAtomic() throws {
    let group=UUID(), first=Clip(duration:bt(2),groupID:group), second=Clip(duration:bt(2),groupID:group)
    let doc=ProjectDocument(sequence:.init(tracks:[Track(name:"One",kind:.audio,clips:[first]),Track(name:"Two",kind:.audio,clips:[second],isLocked:true)]))
    let editor=ProjectEditor(document:doc)
    #expect(throws:DocumentError.lockedTrack) { try editor.perform(.moveMany(clipIDs:[first.id],delta:bt(1))) }
    #expect(editor.document == doc); #expect(!editor.canUndo)
    #expect(throws:DocumentError.lockedTrack) { try editor.perform(.removeMany(clipIDs:[first.id])) }
    #expect(editor.document == doc)
    let following=Clip(start:bt(3),duration:bt(2)), moving=Clip(duration:bt(2))
    let collision=ProjectDocument(sequence:.init(tracks:[Track(name:"Audio",kind:.audio,clips:[moving,following])]))
    let other=ProjectEditor(document:collision)
    #expect(throws:DocumentError.overlap) { try other.perform(.moveMany(clipIDs:[moving.id],delta:bt(2))) }
    #expect(other.document == collision)
    try other.perform(.moveMany(clipIDs:[moving.id,following.id],delta:bt(3)))
    #expect(other.document.sequence.tracks[0].clips.map(\.start) == [bt(3),bt(6)])
}
@MainActor @Test func groupsPersistRemoveAndUndoExactly() throws {
    let a=Clip(duration:bt(1)), b=Clip(start:bt(2),duration:bt(1))
    let doc=ProjectDocument(sequence:.init(tracks:[Track(name:"A",kind:.audio,clips:[a,b])],markers:[Marker(time:bt(0),clipID:a.id)]))
    let editor=ProjectEditor(document:doc)
    try editor.perform(.group(clipIDs:[a.id,b.id]))
    let grouped=editor.document
    #expect(grouped.sequence.tracks[0].clips[0].groupID != nil)
    #expect(grouped.sequence.tracks[0].clips[0].groupID == grouped.sequence.tracks[0].clips[1].groupID)
    #expect(try ProjectDocument.decode(grouped.encoded()) == grouped)
    try editor.perform(.moveMany(clipIDs:[a.id],delta:bt(1)))
    #expect(editor.document.sequence.tracks[0].clips.map(\.start) == [bt(1),bt(3)])
    editor.undo(); #expect(editor.document == grouped)
    try editor.perform(.removeMany(clipIDs:[a.id]))
    #expect(editor.document.sequence.tracks[0].clips.isEmpty)
    #expect(editor.document.sequence.markers.isEmpty)
    editor.undo(); #expect(editor.document == grouped)
    try editor.perform(.ungroup(clipIDs:[a.id]))
    #expect(editor.document.sequence.tracks[0].clips.allSatisfy { $0.groupID == nil })
}
@MainActor @Test func linkRequiresAlignedDurationsAndSupportsExactUndo() throws {
    let a=Clip(duration:bt(2)), b=Clip(duration:bt(2))
    let doc=ProjectDocument(sequence:.init(tracks:[Track(name:"V",kind:.video,clips:[a]),Track(name:"A",kind:.audio,clips:[b])]))
    let editor=ProjectEditor(document:doc)
    try editor.perform(.link(clipIDs:[a.id,b.id]))
    #expect(editor.document.sequence.tracks.flatMap(\.clips).allSatisfy { $0.linkID != nil })
    editor.undo(); #expect(editor.document == doc)
    var bad=doc; bad.sequence.tracks[1].clips[0].duration=bt(1)
    let other=ProjectEditor(document:bad)
    #expect(throws:DocumentError.invalidTiming) { try other.perform(.link(clipIDs:[a.id,b.id])) }
    #expect(other.document == bad)
}
@MainActor @Test func slipAndRollPreserveBoundariesAndRejectSourceOverflow() throws {
    let asset=MediaAsset(url:URL(fileURLWithPath:"/tmp/source.mov"),kind:.video,duration:bt(20))
    let left=Clip(assetID:asset.id,duration:bt(5),sourceStart:bt(2)), right=Clip(assetID:asset.id,start:bt(5),duration:bt(5),sourceStart:bt(8),volume:.init(points:[AutomationPoint(time:.zero,value:0),AutomationPoint(time:bt(5),value:1)]))
    let doc=ProjectDocument(sequence:.init(tracks:[Track(name:"V",kind:.video,clips:[left,right])]),assets:[asset]), editor=ProjectEditor(document:doc)
    try editor.perform(.slip(clipID:left.id,by:bt(1)))
    #expect(editor.document.sequence.tracks[0].clips[0].sourceStart == bt(3))
    #expect(editor.document.sequence.tracks[0].clips[0].start == .zero)
    editor.undo(); #expect(editor.document == doc)
    #expect(throws:DocumentError.sourceBoundary) { try editor.perform(.slip(clipID:left.id,by:bt(30))) }
    #expect(editor.document == doc)
    try editor.perform(.roll(leftClipID:left.id,rightClipID:right.id,to:bt(6)))
    let result=editor.document.sequence.tracks[0].clips
    #expect(result[0].duration == bt(6)); #expect(result[1].start == bt(6)); #expect(result[1].end == bt(10))
    #expect(result[1].sourceStart == bt(9)); #expect(result[1].volume.value(at:.zero) == 0.2)
    editor.undo(); #expect(editor.document == doc)
}
@MainActor @Test func rollingLinkedTracksMovesBothBoundariesAndUndoes() throws {
    let leftLink=UUID(), rightLink=UUID(), asset=MediaAsset(url:URL(fileURLWithPath:"/tmp/av.mov"),kind:.video,duration:bt(20))
    let vl=Clip(assetID:asset.id,duration:bt(4),linkID:leftLink), vr=Clip(assetID:asset.id,start:bt(4),duration:bt(4),sourceStart:bt(4),linkID:rightLink)
    var al=vl, ar=vr; al.id=UUID(); ar.id=UUID()
    let doc=ProjectDocument(sequence:.init(tracks:[Track(name:"V",kind:.video,clips:[vl,vr]),Track(name:"A",kind:.audio,clips:[al,ar])]),assets:[asset])
    let editor=ProjectEditor(document:doc)
    try editor.perform(.roll(leftClipID:vl.id,rightClipID:vr.id,to:bt(5)))
    for track in editor.document.sequence.tracks { #expect(track.clips.map(\.start) == [.zero,bt(5)]); #expect(track.clips.map(\.duration) == [bt(5),bt(3)]) }
    editor.undo(); #expect(editor.document == doc)
}
