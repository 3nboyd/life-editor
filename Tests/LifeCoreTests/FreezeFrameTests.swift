import Testing
import Foundation
import LifeCore
private func ft(_ value:Int64,_ scale:Int64=1)->RationalTime{.init(value:value,timescale:scale)}
@MainActor @Test func freezeFrameExplicitBoundaryPersistsUndoAndTrimSplitClock() throws {
    let asset=MediaAsset(url:URL(fileURLWithPath:"/tmp/original.mov"),kind:.video,duration:ft(2)),clip=Clip(assetID:asset.id,duration:ft(2),opacity:.init(points:[.init(time:.zero,value:0),.init(time:ft(2),value:1)]))
    let document=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Video",kind:.video,clips:[clip])]),assets:[asset]),editor=ProjectEditor(document:document)
    try editor.perform(.extendFreezeFrame(clipID:clip.id,duration:ft(3),sourceFrameTime:ft(59,30)))
    let frozen=try #require(editor.document.sequence.tracks[0].clips.last)
    #expect(frozen.start==clip.end && frozen.duration==ft(3));#expect(frozen.audioEnabled==false && frozen.linkID==nil)
    #expect(try frozen.checkedSourceTime(at:ft(4))==ft(59,30));#expect(frozen.opacity.value(at:.zero)==1)
    #expect(try JSONDecoder().decode(ProjectDocument.self,from:JSONEncoder().encode(editor.document))==editor.document)
    editor.undo();#expect(editor.document==document);editor.redo()
    try editor.perform(.split(clipID:frozen.id,at:ft(3)))
    let right=try #require(editor.document.sequence.tracks[0].clips.first{$0.start==ft(3)})
    #expect(right.freezeFrame?.effectTimeOffset==ft(3));#expect(right.sourceTime(at:ft(4))==ft(59,30))
    try editor.perform(.trim(clipID:right.id,start:ft(4),end:ft(5)))
    #expect(editor.document.sequence.tracks[0].clips.first{$0.id==right.id}?.freezeFrame?.effectTimeOffset==ft(4))
    #expect(throws:DocumentError.self){try editor.perform(.retime(clipID:right.id,speed:2,preservesPitch:true))}
    #expect(throws:DocumentError.self){try editor.perform(.slip(clipID:right.id,by:ft(1)))}
    let data=try JSONEncoder().encode(document);#expect(try JSONDecoder().decode(ProjectDocument.self,from:data).sequence.tracks[0].clips[0].freezeFrame==nil)
}
@MainActor @Test func freezeFrameRejectsUsableHandlesLockedOverlapAndInvalidFramesAtomically() throws {
    let asset=MediaAsset(url:URL(fileURLWithPath:"/tmp/video.mov"),kind:.video,duration:ft(2)),clip=Clip(assetID:asset.id,duration:ft(1))
    let initial=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Video",kind:.video,clips:[clip])]),assets:[asset]),editor=ProjectEditor(document:initial)
    #expect(throws:DocumentError.self){try editor.perform(.extendFreezeFrame(clipID:clip.id,duration:ft(1),sourceFrameTime:ft(59,30)))}
    #expect(editor.document==initial)
    var tail=initial;tail.sequence.tracks[0].clips[0].duration=ft(599,300) // less than a project frame remains
    let allowed=try FreezeFrameEditing.extending(clipID:clip.id,duration:ft(1),sourceFrameTime:ft(59,30),in:tail);try allowed.validate()
    var multicam=tail;multicam.sequence.multicamGroups=[MulticamGroup(angleAssetIDs:[asset.id])]
    #expect(throws:DocumentError.self){try FreezeFrameEditing.extending(clipID:clip.id,duration:ft(1),sourceFrameTime:ft(59,30),in:multicam)}
    tail.sequence.tracks[0].isLocked=true
    #expect(throws:DocumentError.self){try FreezeFrameEditing.extending(clipID:clip.id,duration:ft(1),sourceFrameTime:ft(59,30),in:tail)}
    tail.sequence.tracks[0].isLocked=false;tail.sequence.tracks[0].clips.append(Clip(start:ft(2),duration:ft(1),title:TitleContent(text:"Occupied")))
    #expect(throws:DocumentError.self){try FreezeFrameEditing.extending(clipID:clip.id,duration:ft(1),sourceFrameTime:ft(59,30),in:tail)}
}

@Test func freezeFrameLateSourceValidationAndOverwriteFragmentClock()throws{
    let asset=MediaAsset(url:URL(fileURLWithPath:"/tmp/long.mov"),kind:.video,duration:ft(86400)),frozen=Clip(assetID:asset.id,duration:ft(7200),sourceStart:ft(86399),audioEnabled:false,freezeFrame:.init(sourceTime:ft(86399),effectTimeOffset:ft(2)))
    var document=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Video",kind:.video,clips:[frozen])]),assets:[asset]);try document.validate()
    let overlay=Clip(start:ft(8000),duration:ft(1),title:TitleContent(text:"Cut"));document.sequence.tracks[0].clips.append(overlay)
    let proposal=try SpliceEditing.proposal(for:.overwriteCopies(clipIDs:[overlay.id],at:ft(1)),in:document)
    let right=try #require(proposal.document.sequence.tracks[0].clips.first{$0.freezeFrame != nil && $0.start==ft(2)})
    #expect(right.freezeFrame?.effectTimeOffset==ft(4));#expect(right.sourceTime(at:ft(10))==ft(86399))
}
