import Foundation
import Testing
@testable import LifeCore

@MainActor struct SpliceEditingTests {
    private func t(_ n:Int64,_ d:Int64=1)->RationalTime {.init(value:n,timescale:d)}
    @Test func insertSplitsLinkedCrossingsCopiesSourceMarkersAndUndoesExactly() throws {
        let asset=MediaAsset(url:URL(fileURLWithPath:"/tmp/splice.mov"),kind:.video,duration:t(30))
        let link=UUID(),group=UUID()
        let envelope=AutomationEnvelope(points:[.init(time:t(0),value:1),.init(time:t(10),value:0)])
        let long=Clip(assetID:asset.id,duration:t(10),sourceStart:t(2),speed:0.5,linkID:link,volume:envelope,groupID:group)
        var partner=long;partner.id=UUID()
        let selected=Clip(start:t(12),duration:t(2),title:.init(text:"Hello",animation:.init(kind:.typewriter,duration:2)),groupID:group)
        // Group expansion deliberately copies all three clips, keeping their internal gaps.
        let original=ProjectDocument(sequence:.init(tracks:[.init(name:"Video",kind:.video,clips:[long,selected]),.init(name:"Audio",kind:.audio,clips:[partner])],markers:[.init(time:t(4),duration:t(1),name:"source",clipID:long.id)]),assets:[asset])
        let proposal=try SpliceEditing.proposal(for:.insertCopies(clipIDs:[selected.id],at:t(4)),in:original)
        #expect(proposal.duration==t(14));#expect(proposal.affectedTrackIDs.count==2);#expect(proposal.insertedClipIDs.count==3)
        let video=proposal.document.sequence.tracks[0].clips
        let left=try #require(video.first{$0.id==long.id})
        let right=try #require(video.first{$0.start==t(18) && !proposal.insertedClipIDs.contains($0.id)})
        #expect(left.duration==t(4));#expect(right.sourceStart==t(4));#expect(right.duration==t(6));#expect(right.speed==0.5)
        #expect(right.volume.value(at:t(1))==long.volume.value(at:t(5)))
        let audioRight=try #require(proposal.document.sequence.tracks[1].clips.first{$0.start==t(18) && !proposal.insertedClipIDs.contains($0.id)})
        #expect(audioRight.linkID==right.linkID);#expect(right.linkID != left.linkID)
        let copiedLong=try #require(video.first{proposal.insertedClipIDs.contains($0.id) && $0.assetID==asset.id})
        #expect(copiedLong.sourceStart==long.sourceStart);#expect(copiedLong.linkID != link)
        #expect(proposal.document.sequence.markers.contains{$0.clipID==copiedLong.id && $0.time==t(4)})
        let editor=ProjectEditor(document:original);try editor.perform(.replace(proposal.document));editor.undo();#expect(editor.document==original);editor.redo();#expect(editor.document==proposal.document)
        #expect(try ProjectDocument.decode(proposal.document.encoded())==proposal.document)
    }
    @Test func overwritePreservesGapsAndTrimmedAnimationAndAnnotationWindows() throws {
        let selectedA=Clip(start:t(10),duration:t(1),title:.init(text:"A"))
        let selectedB=Clip(start:t(12),duration:t(1),title:.init(text:"B"))
        let victim=Clip(duration:t(5),title:.init(text:"Victim",animation:.init(kind:.fade,duration:5)),groupID:nil)
        let group=UUID();var a=selectedA,b=selectedB;a.groupID=group;b.groupID=group
        let marker=Marker(time:t(1,2),duration:t(4),name:"range",clipID:victim.id)
        let original=ProjectDocument(sequence:.init(tracks:[.init(name:"Titles",kind:.title,clips:[victim,a,b])],markers:[marker]))
        let proposal=try SpliceEditing.proposal(for:.overwriteCopies(clipIDs:[a.id],at:t(1)),in:original)
        let survivors=proposal.document.sequence.tracks[0].clips.filter{!proposal.insertedClipIDs.contains($0.id) && $0.title?.text=="Victim"}
        #expect(survivors.map(\.start)==[t(0),t(2),t(4)]);#expect(survivors.map(\.duration)==[t(1),t(1),t(1)])
        #expect(survivors[1].title?.animation?.evaluationOffset==t(2))
        #expect(proposal.document.sequence.markers.filter{$0.name=="range"}.count==3)
        #expect(proposal.document.sequence.tracks[0].clips.contains{$0.id==a.id && $0.start==t(10)})
        let editor=ProjectEditor(document:original);try editor.perform(.overwriteCopies(clipIDs:[a.id],at:t(1)));editor.undo();#expect(editor.document==original)
    }
    @Test func rippleTrimKeepsStartAndSourcePrecisionAndMovesOnlyAffectedTracks() throws {
        let asset=MediaAsset(url:URL(fileURLWithPath:"/tmp/source.wav"),kind:.audio,duration:t(20))
        let clip=Clip(start:t(1),duration:t(4),sourceStart:t(2),speed:2,preservesPitch:true,volume:.init(points:[.init(time:.zero,value:1),.init(time:t(4),value:0)]))
        var source=clip;source.assetID=asset.id
        let later=Clip(start:t(7),duration:t(1),title:.init(text:"later"))
        let untouched=Track(name:"Unrelated",kind:.title,clips:[.init(start:t(6),duration:t(1),title:.init(text:"fixed"))])
        let document=ProjectDocument(sequence:.init(tracks:[.init(name:"Audio",kind:.audio,clips:[source,later]),untouched],markers:[.init(time:t(8),name:"global")]),assets:[asset])
        let start=t(48001,48000),end=t(4)
        let result=try SpliceEditing.proposal(for:.rippleTrim(clipID:source.id,start:start,end:end),in:document)
        let edited=result.document.sequence.tracks[0].clips[0]
        #expect(edited.start==source.start);#expect(edited.sourceStart==t(48001,24000));#expect(edited.duration==end-start)
        #expect(edited.volume.value(at:t(1))==source.volume.value(at:t(1)+start-source.start))
        #expect(edited.preservesPitch);#expect(result.document.sequence.tracks[1]==untouched)
        #expect(result.document.sequence.tracks[0].clips[1].start==t(7)+(end-start)-source.duration)
        #expect(result.document.sequence.markers==document.sequence.markers)
        let editor=ProjectEditor(document:document);try editor.perform(.rippleTrim(clipID:source.id,start:start,end:end));editor.undo();#expect(editor.document==document)
        #expect(throws:DocumentError.sourceBoundary){try editor.perform(.rippleTrim(clipID:source.id,start:t(0),end:t(15)))}
        #expect(editor.document==document)
    }
    @Test func sampleInsertAndVisualTailPaddingPreserveExactMappings() throws {
        let asset=MediaAsset(url:URL(fileURLWithPath:"/tmp/precision.wav"),kind:.audio,duration:t(10))
        let long=Clip(assetID:asset.id,duration:t(1)),copy=Clip(assetID:asset.id,start:t(2),duration:t(1,48000))
        let audio=ProjectDocument(sequence:.init(tracks:[.init(name:"Audio",kind:.audio,clips:[long,copy])]),assets:[asset])
        let sample=try SpliceEditing.proposal(for:.insertCopies(clipIDs:[copy.id],at:t(17,48000)),in:audio)
        #expect(sample.duration==t(1,48000))
        let right=try #require(sample.document.sequence.tracks[0].clips.first{$0.start==t(18,48000)})
        #expect(right.sourceStart==t(17,48000));#expect(right.duration==t(47983,48000))
        let group=UUID(),video=Clip(start:t(5),duration:t(1),title:.init(text:"video"),groupID:group)
        let tail=Clip(assetID:asset.id,start:t(5),duration:t(48001,48000),groupID:group)
        let visual=ProjectDocument(sequence:.init(tracks:[.init(name:"Video",kind:.title,clips:[video]),.init(name:"Audio",kind:.audio,clips:[tail])]),assets:[asset])
        let padded=try SpliceEditing.proposal(for:.insertCopies(clipIDs:[video.id],at:t(1)),in:visual)
        #expect(padded.duration==t(31,30))
        #expect(padded.document.sequence.tracks[0].clips.first{$0.id==video.id}?.start==t(181,30))
        let copiedTail=try #require(padded.document.sequence.tracks[1].clips.first{padded.insertedClipIDs.contains($0.id)})
        #expect(copiedTail.duration==tail.duration)
        var multicam=audio;multicam.sequence.multicamGroups=[.init(angleAssetIDs:[asset.id])]
        #expect(throws:SpliceError.self){try SpliceEditing.proposal(for:.insertCopies(clipIDs:[copy.id],at:t(1)),in:multicam)}
    }
    @Test func retainedTransitionTracksSurvivingBoundaryFragments() throws {
        let asset=MediaAsset(url:URL(fileURLWithPath:"/tmp/handles.mov"),kind:.video,duration:t(10))
        let left=Clip(assetID:asset.id,duration:t(2),sourceStart:t(2)),right=Clip(assetID:asset.id,start:t(2),duration:t(2),sourceStart:t(2))
        let copy=Clip(start:t(5),duration:t(1),title:.init(text:"insert"))
        let track=Track(name:"Video",kind:.video,clips:[left,right,copy])
        let transition=VideoTransition(kind:.crossDissolve,trackID:track.id,leftClipID:left.id,rightClipID:right.id,duration:t(1,2))
        let original=ProjectDocument(sequence:.init(tracks:[track],transitions:[transition]),assets:[asset])
        let result=try SpliceEditing.proposal(for:.insertCopies(clipIDs:[copy.id],at:t(1)),in:original)
        let preserved=try #require(result.document.sequence.transitions?.first)
        #expect(preserved.id==transition.id);#expect(preserved.leftClipID != left.id);#expect(preserved.rightClipID==right.id)
        #expect(TransitionResolver.resolve(preserved,in:result.document)?.center==t(3))
    }
    @Test func lockedAndCrossTrackRelationshipsRejectWithoutAnyMutation() throws {
        let link=UUID()
        let a=Clip(duration:t(4),linkID:link,title:.init(text:"a")),b=Clip(duration:t(4),linkID:link,title:.init(text:"b"))
        let selection=Clip(start:t(5),duration:t(1),title:.init(text:"copy"))
        let original=ProjectDocument(sequence:.init(tracks:[.init(name:"A",kind:.title,clips:[a,selection]),.init(name:"B",kind:.title,clips:[b])]))
        let editor=ProjectEditor(document:original)
        #expect(throws:SpliceError.self){try editor.perform(.insertCopies(clipIDs:[selection.id],at:t(2)))}
        #expect(editor.document==original);#expect(!editor.canUndo)
        var locked=original;locked.sequence.tracks[0].isLocked=true
        #expect(throws:DocumentError.lockedTrack){try SpliceEditing.proposal(for:.overwriteCopies(clipIDs:[selection.id],at:t(1)),in:locked)}
    }
}
