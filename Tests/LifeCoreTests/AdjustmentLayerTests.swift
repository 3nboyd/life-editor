import Testing
import Foundation
import LifeCore
private func adjTime(_ n:Int64,_ d:Int64=1)->RationalTime{.init(value:n,timescale:d)}
@MainActor @Test func adjustmentLayerAddsPersistsAndUndoesAsOneDocumentCommand()throws{
    let initial=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Title",kind:.title,clips:[Clip(duration:adjTime(5),title:TitleContent(text:"Test"))])])),editor=ProjectEditor(document:initial)
    let candidate=try AdjustmentLayers.adding(at:adjTime(1),duration:adjTime(2),in:initial)
    #expect(candidate.sequence.tracks.last?.kind == .adjustment)
    let clip=try #require(candidate.sequence.tracks.last?.clips.first);try AdjustmentLayers.validate(clip)
    #expect(clip.assetID==nil && clip.audioEnabled==false && clip.opacity.baseValue==1)
    try editor.perform(.replace(candidate));#expect(try ProjectDocument.decode(editor.document.encoded())==candidate)
    editor.undo();#expect(editor.document==initial);editor.redo();#expect(editor.document==candidate)
}
@MainActor @Test func adjustmentClockSurvivesMoveHeadExtensionAndSplitWithoutNewFields()throws{
    let document=try AdjustmentLayers.adding(at:adjTime(1),duration:adjTime(2),in:ProjectDocument()),editor=ProjectEditor(document:document),id=try #require(document.sequence.tracks[0].clips.first?.id)
    try editor.perform(.move(clipID:id,to:adjTime(3)))
    try editor.perform(.trim(clipID:id,start:adjTime(2),end:adjTime(5)))
    let extended=editor.document.sequence.tracks[0].clips[0];#expect(extended.sourceStart==adjTime(-1));#expect(extended.sourceTime(at:adjTime(3)) == .zero)
    try editor.perform(.split(clipID:id,at:adjTime(4)))
    let right=try #require(editor.document.sequence.tracks[0].clips.first{$0.start==adjTime(4)})
    try AdjustmentLayers.validate(right)
    #expect(right.sourceTime(at:adjTime(9,2))==extended.sourceTime(at:adjTime(9,2)))
    #expect(try ProjectDocument.decode(editor.document.encoded())==editor.document)
    var ordinary=editor.document;ordinary.sequence.tracks[0].kind = .title
    #expect(throws:DocumentError.self){try ordinary.validate()}
}
@Test func adjustmentLayerRejectsUnsupportedContentsWithoutMakingLegacyDocumentsUnreadable()throws{
    var clip=Clip(duration:adjTime(1));try AdjustmentLayers.validate(clip)
    clip.title=TitleContent(text:"Saved text")
    #expect(throws:AdjustmentLayerError.invalidContents){try AdjustmentLayers.validate(clip)}
    let preserved=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Old",kind:.adjustment,clips:[clip])]))
    #expect(try ProjectDocument.decode(preserved.encoded())==preserved)
    clip.title=nil;clip.linkID=UUID();#expect(throws:AdjustmentLayerError.invalidContents){try AdjustmentLayers.validate(clip)}
    #expect(throws:DocumentError.self){try AdjustmentLayers.adding(at:adjTime(-1),duration:adjTime(1),in:ProjectDocument())}
}

@Test func adjustmentTransitionMetadataIsPreservedButExplicitlyRejectedForRendering()throws{
    var document=try AdjustmentLayers.adding(at:.zero,duration:adjTime(2),in:ProjectDocument())
    let track=document.sequence.tracks[0],clip=track.clips[0]
    document.sequence.transitions=[VideoTransition(kind:.crossDissolve,trackID:track.id,leftClipID:clip.id,rightClipID:UUID(),duration:adjTime(1))]
    #expect(try ProjectDocument.decode(document.encoded())==document)
    #expect(throws:AdjustmentLayerError.invalidTransition){try AdjustmentLayers.validate(in:document)}
    document.sequence.transitions?[0].isEnabled=false;try AdjustmentLayers.validate(in:document)
}

@MainActor @Test func adjustmentUnsupportedEditingCommandsRejectAtomicallyWhileGroupingWorks()throws{
    var document=try AdjustmentLayers.adding(at:.zero,duration:adjTime(1),in:ProjectDocument())
    let first=document.sequence.tracks[0].clips[0],second=Clip(start:adjTime(1),duration:adjTime(1),audioEnabled:false)
    document.sequence.tracks[0].clips.append(second)
    let title=Clip(duration:adjTime(1),title:TitleContent(text:"Together"));document.sequence.tracks.append(Track(name:"Title",kind:.title,clips:[title]))
    let editor=ProjectEditor(document:document)
    let unsupported:[EditCommand]=[.link(clipIDs:[first.id,title.id]),.retime(clipID:first.id,speed:2,preservesPitch:true),.slip(clipID:first.id,by:adjTime(1)),.roll(leftClipID:first.id,rightClipID:second.id,to:adjTime(1,2))]
    for command in unsupported{#expect(throws:AdjustmentLayerError.invalidContents){try editor.perform(command)};#expect(editor.document==document);#expect(!editor.canUndo)}
    try editor.perform(.group(clipIDs:[first.id,title.id]));try AdjustmentLayers.validate(in:editor.document)
    editor.undo();#expect(editor.document==document)
}
