import Foundation
import Testing
@testable import LifeCore
private func tt(_ n: Int64, _ d: Int64 = 1) -> RationalTime { .init(value:n,timescale:d) }
private func transitionFixture() -> (ProjectDocument,Clip,Clip) {
    let a=MediaAsset(url:URL(fileURLWithPath:"/tmp/a.mov"),kind:.video,duration:tt(20)), b=MediaAsset(url:URL(fileURLWithPath:"/tmp/b.mov"),kind:.video,duration:tt(20))
    let l=Clip(assetID:a.id,duration:tt(5),sourceStart:tt(2)), r=Clip(assetID:b.id,start:tt(5),duration:tt(5),sourceStart:tt(3))
    return (ProjectDocument(sequence:Sequence(tracks:[Track(name:"V",kind:.video,clips:[l,r])]),assets:[a,b]),l,r)
}
@MainActor @Test func transitionsPreserveSequenceTimingPersistAndUndoExactly() throws {
    let (doc,left,right)=transitionFixture(), editor=ProjectEditor(document:transitionFixture().0)
    let actual=ProjectEditor(document:doc)
    try actual.perform(.addTransition(leftClipID:left.id,rightClipID:right.id,kind:.crossDissolve,duration:tt(2)))
    let result=actual.document, transition=try #require(result.sequence.transitions?.first)
    #expect(result.sequence.tracks == doc.sequence.tracks)
    #expect(result.sequence.duration == doc.sequence.duration)
    #expect(try ProjectDocument.decode(result.encoded()) == result)
    let resolved=try #require(TransitionResolver.resolve(transition,in:result))
    #expect(resolved.start == tt(4)); #expect(resolved.center == tt(5)); #expect(resolved.end == tt(6))
    try actual.perform(.setTransitionDuration(id:transition.id,duration:tt(1)))
    actual.undo(); #expect(actual.document == result)
    try actual.perform(.removeTransition(id:transition.id)); actual.undo(); #expect(actual.document == result)
    actual.undo(); #expect(actual.document == doc)
    #expect(editor.document.sequence.transitions == nil)
}
@MainActor @Test func transitionsConstrainFiniteSourceHandlesWithIndependentSpeeds() throws {
    var (doc,left,right)=transitionFixture()
    doc.assets[0].duration=tt(15)
    left.speed=2; left.sourceStart=tt(2) // source end12, spare3=>1.5s handle.
    right.speed=0.5; right.sourceStart=tt(1) // preroll1=>2s handle.
    doc.sequence.tracks[0].clips=[left,right]
    #expect(try TransitionResolver.availableDuration(leftClipID:left.id,rightClipID:right.id,in:doc) == tt(3))
    let editor=ProjectEditor(document:doc)
    #expect(throws:DocumentError.sourceBoundary) { try editor.perform(.addTransition(leftClipID:left.id,rightClipID:right.id,kind:.wipe,duration:tt(4))) }
    #expect(editor.document == doc)
    try editor.perform(.addTransition(leftClipID:left.id,rightClipID:right.id,kind:.wipe,duration:tt(3)))
    #expect(editor.document.sequence.tracks == doc.sequence.tracks)
}
@MainActor @Test func transitionMetadataSurvivesOrphaningAndDoesNotRender() throws {
    let (doc,left,right)=transitionFixture(), editor=ProjectEditor(document:doc)
    try editor.perform(.addTransition(leftClipID:left.id,rightClipID:right.id,kind:.zoom,duration:tt(1)))
    let transition=try #require(editor.document.sequence.transitions?.first)
    try editor.perform(.move(clipID:right.id,to:tt(7)))
    #expect(editor.document.sequence.transitions?.first == transition)
    #expect(TransitionResolver.resolve(transition,in:editor.document) == nil)
    #expect(try ProjectDocument.decode(editor.document.encoded()) == editor.document)
    try editor.perform(.remove(clipID:left.id))
    #expect(editor.document.sequence.transitions?.first == transition)
    #expect(TransitionResolver.resolve(transition,in:editor.document) == nil)
}
@MainActor @Test func transitionNeighborsCannotOverlapAndImagesHaveStaticHandles() throws {
    let asset=MediaAsset(url:URL(fileURLWithPath:"/tmp/photo.png"),kind:.image,duration:tt(5))
    let clips=[Clip(assetID:asset.id,duration:tt(2)),Clip(assetID:asset.id,start:tt(2),duration:tt(2)),Clip(assetID:asset.id,start:tt(4),duration:tt(2))]
    let doc=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Images",kind:.image,clips:clips)]),assets:[asset]), editor=ProjectEditor(document:doc)
    try editor.perform(.addTransition(leftClipID:clips[0].id,rightClipID:clips[1].id,kind:.fadeBlack,duration:tt(3)))
    #expect(try TransitionResolver.availableDuration(leftClipID:clips[1].id,rightClipID:clips[2].id,in:editor.document) == tt(1))
    #expect(throws:DocumentError.sourceBoundary) { try editor.perform(.addTransition(leftClipID:clips[1].id,rightClipID:clips[2].id,kind:.flash,duration:tt(2))) }
    try editor.perform(.addTransition(leftClipID:clips[1].id,rightClipID:clips[2].id,kind:.flash,duration:tt(1)))
    #expect(editor.document.sequence.transitions?.allSatisfy { TransitionResolver.resolve($0,in:editor.document) != nil } == true)
    let still=Clip(assetID:asset.id,start:tt(3),duration:tt(5))
    let extensionDoc=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Still",kind:.image,clips:[still])]),assets:[asset])
    let extend=ProjectEditor(document:extensionDoc)
    try extend.perform(.trim(clipID:still.id,start:tt(1),end:tt(20)))
    #expect(extend.document.sequence.tracks[0].clips[0].duration == tt(19))
    #expect(extend.document.sequence.tracks[0].clips[0].sourceStart == .zero)
}
@Test func oldDocumentsOmitTransitionsAndMalformedTransitionFieldsReject() throws {
    var (doc,left,right)=transitionFixture()
    #expect(try ProjectDocument.decode(doc.encoded()).sequence.transitions == nil)
    doc.sequence.transitions=[VideoTransition(kind:.dipColor,trackID:doc.sequence.tracks[0].id,leftClipID:left.id,rightClipID:right.id,duration:tt(1),direction:9)]
    #expect(throws:DocumentError.invalidTiming) { try doc.validate() }
}
