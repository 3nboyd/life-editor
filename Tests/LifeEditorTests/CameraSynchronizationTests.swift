import Foundation
import Testing
import SwiftUI
import AppKit
import LifeCore
@testable import LifeMedia
@testable import LifeEditor

@MainActor struct CameraSynchronizationTests {
    private func fixture()->(ProjectDocument,UUID,UUID,UUID) {
        let a=MediaAsset(url:URL(fileURLWithPath:"/tmp/camera-a.mov"),kind:.video,duration:.init(value:30,timescale:1))
        let b=MediaAsset(url:URL(fileURLWithPath:"/tmp/camera-b.mov"),kind:.video,duration:.init(value:30,timescale:1))
        let master=MediaAsset(url:URL(fileURLWithPath:"/tmp/master.wav"),kind:.audio,duration:.init(value:30,timescale:1))
        let clips=[Clip(assetID:a.id,start:.init(value:10,timescale:1),duration:.init(value:5,timescale:1),sourceStart:.init(value:2,timescale:1)),Clip(assetID:b.id,start:.init(value:20,timescale:1),duration:.init(value:5,timescale:1),sourceStart:.init(value:4,timescale:1)),Clip(assetID:master.id,start:.init(value:7,timescale:1),duration:.init(value:5,timescale:1),sourceStart:.init(value:1,timescale:1))]
        let tracks=clips.enumerated().map {index,clip in Track(name:"\(index)",kind:index==2 ? .audio:.video,clips:[clip])}
        return (ProjectDocument(sequence:.init(tracks:tracks,multicamGroups:[.init(angleAssetIDs:[a.id,b.id],masterAudioAssetID:master.id)]),assets:[a,b,master]),a.id,b.id,master.id)
    }
    private func reference(_ seconds:Int64,fps:Int64=30)->TimecodeReference {.init(origin:.init(value:seconds,timescale:1),frameDuration:.init(value:1,timescale:fps),frameQuanta:Int(fps),dropFrame:false,wraps24Hours:true)}
    @Test func timecodePrefersActualMasterReferenceAndFallsBackToFirstValidCamera() throws {
        let (document,a,b,master)=fixture()
        let result=try EditorStore.timecodeSynchronization(in:document,references:[master:reference(100),a:reference(105),b:reference(108)])
        #expect(result.referenceID==master)
        #expect(result.candidates.first{$0.assetID==a}?.exactOffset == .init(value:5,timescale:1))
        let store=EditorStore();store.document=document
        #expect(store.installSynchronizationResults(result.candidates,referenceID:result.referenceID,baseline:document))
        let synchronized=try store.synchronizedCandidate()
        #expect(synchronized.sequence.tracks[0].clips[0].start == .init(value:13,timescale:1))
        #expect(synchronized.sequence.tracks[1].clips[0].start == .init(value:18,timescale:1))
        #expect(synchronized.sequence.tracks[2]==document.sequence.tracks[2])
        #expect(store.document==document) // Analysis/proposal never applies an edit.
        let fallback=try EditorStore.timecodeSynchronization(in:document,references:[a:reference(100),b:reference(108)])
        #expect(fallback.referenceID==a)
        #expect(fallback.candidates.first{$0.assetID==master}?.confidence==0)
        #expect(store.installSynchronizationResults(fallback.candidates,referenceID:a,baseline:document))
        #expect(try store.synchronizedCandidate()==document)
    }
    @Test func missingIncompatibleAndDayWrapRemainExplicitManualDecisions() throws {
        let (document,a,b,master)=fixture()
        let unmatched=try EditorStore.timecodeSynchronization(in:document,references:[:])
        #expect(unmatched.referenceID==a);#expect(unmatched.candidates.allSatisfy{$0.confidence==0})
        let incompatible=try EditorStore.timecodeSynchronization(in:document,references:[master:reference(100),a:reference(102),b:reference(104,fps:25)])
        #expect(incompatible.candidates.first{$0.assetID==b}?.note=="Format mismatch")
        #expect(incompatible.candidates.first{$0.assetID==b}?.offset==10)
        let wrapped=try EditorStore.timecodeSynchronization(in:document,references:[master:reference(86399),a:reference(1)])
        let day=try #require(wrapped.candidates.first{$0.assetID==a})
        #expect(day.note=="Day wrap");#expect(day.exactOffset == .init(value:2,timescale:1))
        var manual=day;manual.offset=3.25
        #expect(manual.exactOffset==nil);#expect(manual.offset==3.25)
    }
    @Test func changedSameProjectRejectsBothAsyncResultsAndPreviewApply() throws {
        let (document,a,b,master)=fixture();let store=EditorStore();store.document=document
        let candidates=[CameraSyncCandidate(assetID:a,offset:5,confidence:1),CameraSyncCandidate(assetID:b,offset:8,confidence:1)]
        #expect(store.installSynchronizationResults(candidates,referenceID:master,baseline:document))
        store.document.name="New edit";let edited=store.document
        #expect(throws:SynchronizationPreviewError.stale){try store.synchronizedCandidate()}
        store.applySynchronization();#expect(store.document==edited);#expect(store.error?.contains("Project changed")==true)
        store.cancelSynchronization()
        #expect(!store.installSynchronizationResults(candidates,referenceID:master,baseline:document))
        #expect(store.syncCandidates.isEmpty);#expect(store.syncReferenceID==nil)
        #expect(store.document.id==document.id)
    }
    @Test func synchronizationControlsFitCompactInspector() throws {
        _=NSApplication.shared
        let (document,a,b,master)=fixture(),store=EditorStore();store.document=document;store.syncMethod = .timecode
        let result=try EditorStore.timecodeSynchronization(in:document,references:[master:reference(86399),a:reference(1),b:reference(3)])
        #expect(store.installSynchronizationResults(result.candidates,referenceID:master,baseline:document))
        let host=NSHostingView(rootView:CameraSynchronizationControls(store:store).padding(12).frame(width:268).preferredColorScheme(.dark))
        host.appearance=NSAppearance(named:.darkAqua)
        host.frame=NSRect(x:0,y:0,width:268,height:360);host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width<=268);#expect(host.fittingSize.height<=360)
        let bitmap=try #require(host.bitmapImageRepForCachingDisplay(in:host.bounds));host.cacheDisplay(in:host.bounds,to:bitmap)
        let png=try #require(bitmap.representation(using:.png,properties:[:]))
        try png.write(to:URL(fileURLWithPath:"/tmp/life-editor-ui-checks/timecode-sync.png"))
    }
}
