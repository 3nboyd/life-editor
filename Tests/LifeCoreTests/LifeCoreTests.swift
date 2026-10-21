import Foundation
import Testing
@testable import LifeCore

private func t(_ value: Int64, _ scale: Int64 = 1) -> RationalTime { .init(value:value,timescale:scale) }
@Test func rationalTimingIsExactAcrossAnHour() {
    let ntsc=FrameRate(numerator:30000,denominator:1001)
    var accumulated=RationalTime.zero
    for _ in 0..<107892 { accumulated += ntsc.frameDuration }
    #expect(accumulated == ntsc.time(forFrame:107892))
    #expect(t(1,48000)+t(1,48000) == t(1,24000))
    #expect(t(-1,3) < t(1,9))
    #expect(t(Int64.max,Int64.max-1) > t(Int64.max-1,Int64.max))
}
@Test func invalidTimeDecodingThrows() {
    #expect(throws:(any Error).self) { try JSONDecoder().decode(RationalTime.self,from:Data(#"{"value":1,"timescale":0}"#.utf8)) }
}
@Test func holdEnvelopeChangesAtNextPoint() {
    let envelope=AutomationEnvelope(points:[.init(time:.zero,value:0.2,interpolation:.hold),.init(time:t(1),value:0.8)])
    #expect(envelope.value(at:t(999,1000)) == 0.2)
    #expect(envelope.value(at:t(1)) == 0.8)
}
@MainActor @Test func splitKeepsSourceAndLinearEnvelopeAndUndoesExactly() throws {
    let clip=Clip(duration:t(10),sourceStart:t(2),volume:.init(points:[.init(time:.zero,value:0),.init(time:t(10),value:1)]))
    let initial=ProjectDocument(sequence:.init(tracks:[.init(name:"Video",kind:.video,clips:[clip])]))
    let editor=ProjectEditor(document:initial)
    try editor.perform(.split(clipID:clip.id,at:t(4)))
    let clips=editor.document.sequence.tracks[0].clips
    #expect(clips.count == 2)
    #expect(clips[1].sourceStart == t(6))
    #expect(clips[1].volume.value(at:t(1)) == 0.5)
    editor.undo(); #expect(editor.document == initial)
    editor.redo(); #expect(editor.document.sequence.tracks[0].clips == clips)
}
@MainActor @Test func unsafePlacementIsAtomicAndLinksMoveTogether() throws {
    let link=UUID(), video=Clip(start:t(1),duration:t(2),linkID:link), audio=Clip(start:t(1),duration:t(2),linkID:link)
    let other=Clip(start:t(5),duration:t(2))
    let initial=ProjectDocument(sequence:.init(tracks:[.init(name:"Video",kind:.video,clips:[video,other]),.init(name:"Audio",kind:.audio,clips:[audio])]))
    let editor=ProjectEditor(document:initial)
    #expect(throws:DocumentError.overlap) { try editor.perform(.move(clipID:video.id,to:t(4))) }
    #expect(editor.document == initial)
    #expect(!editor.canUndo)
    try editor.perform(.move(clipID:video.id,to:t(2)))
    #expect(editor.document.sequence.tracks[1].clips[0].start == t(2))
    #expect(editor.document.sequence.tracks[0].clips[1] == other)
}
@MainActor @Test func trimRejectsManufacturedSource() throws {
    let asset=MediaAsset(url:URL(fileURLWithPath:"/tmp/example.wav"),kind:.audio,duration:t(5))
    let clip=Clip(assetID:asset.id,duration:t(5))
    let initial=ProjectDocument(sequence:.init(tracks:[.init(name:"Audio",kind:.audio,clips:[clip])]),assets:[asset])
    let editor=ProjectEditor(document:initial)
    #expect(throws:DocumentError.sourceBoundary) { try editor.perform(.trim(clipID:clip.id,start:.zero,end:t(6))) }
    #expect(editor.document == initial)
    try editor.perform(.trim(clipID:clip.id,start:t(1,48000),end:t(5)))
    #expect(editor.document.sequence.tracks[0].clips[0].sourceStart == t(1,48000))
}
@Test func packageRoundtripAndFutureVersionProtection() throws {
    let path=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("lifeedit")
    defer { try? FileManager.default.removeItem(at:path) }
    let document=ProjectDocument(name:"Rehearsal",sequence:.init(tracks:[.init(name:"Title",kind:.title,clips:[.init(duration:t(2),title:.init(text:"Hello"))])]))
    try ProjectPackage.write(document,to:path)
    #expect(try ProjectPackage.read(from:path) == document)
    var future=document; future.version=999
    let futureData=try JSONEncoder().encode(future)
    try futureData.write(to:path.appendingPathComponent(ProjectPackage.projectFilename))
    #expect(throws:DocumentError.unsupportedVersion(999)) { try ProjectPackage.write(document,to:path) }
    #expect(try Data(contentsOf:path.appendingPathComponent(ProjectPackage.projectFilename)) == futureData)
}
@Test func snapshotEvaluationIsIndependentAndUsesHalfOpenRanges() {
    let clip=Clip(start:t(2),duration:t(2),sourceStart:t(1),speed:2)
    var document=ProjectDocument(sequence:.init(tracks:[.init(name:"V1",kind:.video,clips:[clip])]))
    let snapshot=ProjectSnapshot(document:document)
    document.sequence.tracks.removeAll()
    #expect(TimelineEvaluator.evaluate(snapshot,at:t(3)).first?.sourceTime == t(3))
    #expect(TimelineEvaluator.evaluate(snapshot,at:t(4)).isEmpty)
}

@MainActor @Test func videoEditsQuantizeWhileEasedCurvesSurviveSplit() throws {
    let envelope=AutomationEnvelope(points:[.init(time:.zero,value:0,interpolation:.eased),.init(time:t(10),value:1)])
    let clip=Clip(duration:t(10),volume:envelope)
    let editor=ProjectEditor(document:.init(sequence:.init(tracks:[.init(name:"Video",kind:.video,clips:[clip])])))
    try editor.perform(.split(clipID:clip.id,at:t(4001,1000)))
    let right=editor.document.sequence.tracks[0].clips[1]
    #expect(right.start == t(4))
    #expect(right.volume.value(at:t(1)) == envelope.value(at:t(5)))
}

@Test func gainMultipliesAutomationIncludingSilence() {
    var envelope=AutomationEnvelope(baseValue:0.5,points:[.init(time:.zero,value:0),.init(time:t(2),value:1)])
    #expect(envelope.value(at:t(1)) == 0.25)
    envelope.baseValue=0
    #expect(envelope.value(at:t(2)) == 0)
}
@MainActor @Test func replacementCannotBypassOverlapOrSourceBoundary() throws {
    let clip=Clip(duration:t(3))
    let initial=ProjectDocument(sequence:.init(tracks:[.init(name:"Video",kind:.video,clips:[clip])]))
    let editor=ProjectEditor(document:initial)
    var overlap=initial
    overlap.sequence.tracks[0].clips.append(.init(start:t(2),duration:t(2)))
    #expect(throws:DocumentError.overlap) { try editor.perform(.replace(overlap)) }
    #expect(editor.document == initial)
    var tooLong=initial
    let asset=MediaAsset(url:URL(fileURLWithPath:"/tmp/test.mov"),kind:.video,duration:t(2))
    tooLong.assets=[asset]; tooLong.sequence.tracks[0].clips[0].assetID=asset.id
    #expect(throws:DocumentError.sourceBoundary) { try editor.perform(.replace(tooLong)) }
    #expect(editor.document == initial)
}
@Test func malformedHugeTimingIsRejectedBeforeDurationEvaluation() throws {
    var document=ProjectDocument(sequence:.init(tracks:[.init(name:"Video",kind:.video,clips:[.init(duration:t(1))])]))
    document.sequence.tracks[0].clips[0].start=t(Int64.max)
    let data=try JSONEncoder().encode(document)
    #expect(throws:DocumentError.invalidTiming) { try ProjectDocument.decode(data) }
    #expect(throws:DocumentError.invalidTiming) { try t(Int64.max).checkedAdding(t(1)) }
    #expect(throws:DocumentError.invalidTiming) { try t(Int64.max).checkedScaled(by:2) }
}

@MainActor @Test func groupedEditsUndoAsOneExactAction() throws {
    let clip=Clip(duration:t(3))
    let initial=ProjectDocument(sequence:.init(tracks:[.init(name:"Video",kind:.video,clips:[clip])]))
    let editor=ProjectEditor(document:initial)
    editor.beginUndoGroup()
    try editor.perform(.move(clipID:clip.id,to:t(1)))
    try editor.perform(.move(clipID:clip.id,to:t(2)))
    editor.undo() // An in-flight gesture cannot be partly undone.
    #expect(editor.document.sequence.tracks[0].clips[0].start == t(2))
    editor.endUndoGroup()
    let final=editor.document
    editor.undo(); #expect(editor.document == initial); #expect(!editor.canUndo)
    editor.redo(); #expect(editor.document == final)
}

@MainActor @Test func retimePreservesFullSourceAndIsExactlyUndoable() throws {
    let asset=MediaAsset(url:URL(fileURLWithPath:"/tmp/audio.wav"),kind:.audio,duration:t(1))
    let envelope=AutomationEnvelope(points:[.init(time:.zero,value:0),.init(time:t(2),value:1)],evaluationOffset:t(1))
    let clip=Clip(assetID:asset.id,duration:t(1),volume:envelope,opacity:envelope)
    let untouched=Clip(start:t(4),duration:t(1))
    let initial=ProjectDocument(sequence:.init(tracks:[.init(name:"Audio",kind:.audio,clips:[clip]),.init(name:"Other",kind:.audio,clips:[untouched])]),assets:[asset])
    let editor=ProjectEditor(document:initial)
    try editor.perform(.retime(clipID:clip.id,speed:1.1,preservesPitch:false))
    let result=editor.document.sequence.tracks[0].clips[0]
    #expect(result.duration == t(10,11))
    #expect(try result.checkedSourceTime(at:result.end) == t(1))
    #expect(result.volume.evaluationOffset == t(10,11))
    #expect(result.volume.points[1].time == t(20,11))
    #expect(result.volume.value(at:t(5,11)) == envelope.value(at:t(1,2)))
    #expect(!result.preservesPitch)
    #expect(editor.document.sequence.tracks[1].clips[0] == untouched)
    editor.undo(); #expect(editor.document == initial)
    editor.redo()
    try editor.perform(.retime(clipID:clip.id,speed:1,preservesPitch:true))
    #expect(editor.document == initial)
}
@MainActor @Test func retimeRejectsOverlapAndLockedTrackWithoutMutation() throws {
    let clip=Clip(duration:t(1)), neighbor=Clip(start:t(1),duration:t(1))
    let initial=ProjectDocument(sequence:.init(tracks:[.init(name:"Audio",kind:.audio,clips:[clip,neighbor])]))
    let editor=ProjectEditor(document:initial)
    #expect(throws:DocumentError.overlap) { try editor.perform(.retime(clipID:clip.id,speed:0.5,preservesPitch:true)) }
    #expect(editor.document == initial); #expect(!editor.canUndo)
    var locked=initial; locked.sequence.tracks[0].isLocked=true
    let lockedEditor=ProjectEditor(document:locked)
    #expect(throws:DocumentError.lockedTrack) { try lockedEditor.perform(.retime(clipID:clip.id,speed:2,preservesPitch:true)) }
    #expect(lockedEditor.document == locked); #expect(!lockedEditor.canUndo)
}

@Test func incompatibleEnvelopeTimeArithmeticIsRejected() throws {
    let envelope=AutomationEnvelope(points:[
        .init(time:t(80_000_000_000_001,999_999_937),value:0),
        .init(time:t(80_000_000_000_000,999_999_929),value:1)
    ])
    let document=ProjectDocument(sequence:.init(tracks:[.init(name:"Audio",kind:.audio,clips:[.init(duration:t(1),volume:envelope)])]))
    #expect(throws:DocumentError.invalidTiming) { try document.validate() }
}
