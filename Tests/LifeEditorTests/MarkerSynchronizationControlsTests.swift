import Testing
import Foundation
import LifeCore
@testable import LifeEditor
@MainActor @Test func markerSyncReviewsOneRecordingAndPreservesOtherAnglesWithExactUndo()throws{
    let time:RationalTime = .init(value:1,timescale:1)
    let camera=MediaAsset(url:URL(fileURLWithPath:"/tmp/ref.mov"),kind:.video,duration:time.scaled(by:20))
    let target=MediaAsset(url:URL(fileURLWithPath:"/tmp/target.wav"),kind:.audio,duration:time.scaled(by:20))
    let other=MediaAsset(url:URL(fileURLWithPath:"/tmp/other.mov"),kind:.video,duration:time.scaled(by:20))
    let a=Clip(assetID:camera.id,start:time.scaled(by:10),duration:time.scaled(by:5))
    let b=Clip(assetID:target.id,duration:time.scaled(by:5))
    let c=Clip(assetID:other.id,start:time.scaled(by:30),duration:time.scaled(by:5))
    let reference=Marker(time:time.scaled(by:2),clipID:a.id),aligned=Marker(time:time,clipID:b.id)
    let document=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Ref",kind:.video,clips:[a]),Track(name:"Target",kind:.audio,clips:[b]),Track(name:"Other",kind:.video,clips:[c])],markers:[reference,aligned],multicamGroups:[.init(angleAssetIDs:[camera.id,other.id],masterAudioAssetID:target.id)]),assets:[camera,target,other])
    let store=EditorStore();store.replace(document)
    store.prepareMarkerSynchronization(reference:reference.id,target:aligned.id)
    #expect(store.document==document);#expect(store.syncCandidates.count==1)
    let candidate=try store.synchronizedCandidate()
    #expect(candidate.sequence.tracks[1].clips[0].start==time.scaled(by:11))
    #expect(candidate.sequence.tracks[0]==document.sequence.tracks[0]);#expect(candidate.sequence.tracks[2]==document.sequence.tracks[2])
    store.applySynchronization();#expect(store.document==candidate)
    store.undo();#expect(store.document==document)
    store.prepareMarkerSynchronization(reference:reference.id,target:aligned.id)
    store.document.name="Later edit"
    #expect(throws:SynchronizationPreviewError.stale){try store.synchronizedCandidate()}
}
