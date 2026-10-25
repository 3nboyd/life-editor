import Foundation
import Testing
import LifeCore
@testable import LifeEditor

@MainActor @Test func driftReviewUsesCreatedMulticamPreservesMasterAndAllowsManualOffsetAfterApply()throws {
    let a=MediaAsset(url:URL(fileURLWithPath:"/cameraA.mov"),kind:.video,duration:.init(value:600,timescale:1))
    let b=MediaAsset(url:URL(fileURLWithPath:"/cameraB.mov"),kind:.video,duration:.init(value:600,timescale:1))
    let master=MediaAsset(url:URL(fileURLWithPath:"/master.wav"),kind:.audio,duration:.init(value:600,timescale:1))
    let document=ProjectDocument(sequence:Sequence(tracks:[Track(name:"A",kind:.video,clips:[Clip(assetID:a.id,duration:.init(value:100,timescale:1)),Clip(assetID:a.id,start:.init(value:100,timescale:1),duration:.init(value:500,timescale:1),sourceStart:.init(value:100,timescale:1))]),Track(name:"B",kind:.video,clips:[Clip(assetID:b.id,duration:b.duration)]),Track(name:"Master",kind:.audio,clips:[Clip(assetID:master.id,duration:master.duration)])]),assets:[a,b,master])
    let store=EditorStore();store.replace(document);store.createMulticam()
    let baseline=store.document
    func anchor(_ source:Double)->DriftAnchor{.init(sourceSeconds:source,referenceSeconds:2+source*0.999,confidence:0.9,uncertaintySeconds:0.023)}
    let correction=try AffineDriftCorrection.fit(early:anchor(20),middle:anchor(200),late:anchor(400))
    #expect(store.installSynchronizationResults([.init(assetID:a.id,offset:correction.sourceOrigin,confidence:0.9,correction:correction)],referenceID:master.id,baseline:baseline))
    #expect(store.syncCandidates[0].correctDrift==false)
    let translation=try store.synchronizedCandidate()
    #expect(translation.sequence.tracks[0].clips[0].speed==1)
    store.syncCandidates[0].correctDrift=true
    let preview=try store.synchronizedCandidate()
    #expect(store.document==baseline)
    #expect(preview.sequence.tracks[0].clips[0].speed==correction.speed)
    #expect(preview.sequence.tracks[0].clips[0].end==preview.sequence.tracks[0].clips[1].start)
    #expect(preview.sequence.tracks[1]==baseline.sequence.tracks[1])
    #expect(preview.sequence.tracks[2]==baseline.sequence.tracks[2])
    #expect(preview.sequence.multicamGroups==baseline.sequence.multicamGroups)
    store.applySynchronization();#expect(store.document==preview)
    store.prepareManualSynchronization()
    let index=try #require(store.syncCandidates.firstIndex{$0.assetID==a.id})
    store.syncCandidates[index].offset+=0.125
    let translated=try store.synchronizedCandidate()
    #expect(translated.sequence.tracks[0].clips[0].speed==correction.speed)
    #expect(translated.sequence.tracks[0].clips[0].end==translated.sequence.tracks[0].clips[1].start)
    #expect(abs(translated.sequence.tracks[0].clips[0].start.seconds-preview.sequence.tracks[0].clips[0].start.seconds-0.125)<1.0/48000)
    #expect(translated.sequence.tracks[2]==baseline.sequence.tracks[2])
    store.cancelSynchronization();#expect(store.document==preview)
    store.undo();#expect(store.document==baseline)
    store.redo();#expect(store.document==preview)
    store.prepareManualSynchronization()
    var edited=store.document;edited.sequence.tracks[2].isMuted=true;store.replace(edited)
    #expect(throws:SynchronizationPreviewError.stale){try store.synchronizedCandidate()}
}
