import Testing
import Foundation
import LifeCore
@testable import LifeEditor

@MainActor private func switchingStore()->(EditorStore,MediaAsset,MediaAsset,MediaAsset){
    let duration=RationalTime(value:4,timescale:1)
    let a=MediaAsset(url:URL(fileURLWithPath:"/tmp/life-ui-angle-a.mov"),kind:.video,duration:duration)
    let b=MediaAsset(url:URL(fileURLWithPath:"/tmp/life-ui-angle-b.mov"),kind:.video,duration:duration)
    let master=MediaAsset(url:URL(fileURLWithPath:"/tmp/life-ui-master.wav"),kind:.audio,duration:duration)
    let group=MulticamGroup(angleAssetIDs:[a.id,b.id],masterAudioAssetID:master.id,cuts:[.init(time:.zero,angleID:a.id),.init(time:.init(value:2,timescale:1),angleID:b.id)],audioAssetIDs:[master.id],audioCuts:[.init(time:.init(value:2,timescale:1),angleID:b.id)])
    let document=ProjectDocument(sequence:Sequence(tracks:[Track(name:"A",kind:.video,clips:[Clip(assetID:a.id,duration:duration)]),Track(name:"B",kind:.video,clips:[Clip(assetID:b.id,duration:duration)]),Track(name:"Master",kind:.audio,clips:[Clip(assetID:master.id,duration:duration)])],multicamGroups:[group]),assets:[a,b,master])
    let store=EditorStore();store.replace(document);store.cameraAudioIDs=[a.id,b.id,master.id];store.checkingCameraAudio=false
    return(store,a,b,master)
}
@MainActor @Test func multicamModesWriteOnlyTheirSelectedDecisionLanesAndRejectMissingAudio() throws {
    let(store,a,b,master)=switchingStore();let original=store.document.sequence.multicamGroups[0]
    store.switchMode = .audio;store.switchArmed=true;store.playhead=1
    store.chooseAngle(b.id)
    #expect(store.document.sequence.multicamGroups[0].cuts==original.cuts)
    #expect(MulticamSwitching.selectedAudio(in:store.document.sequence.multicamGroups[0],at:.init(value:1,timescale:1))==b.id)
    store.switchMode = .video;store.playhead=1.5;let audio=store.document.sequence.multicamGroups[0].audioCuts
    store.chooseAngle(b.id)
    #expect(store.document.sequence.multicamGroups[0].audioCuts==audio)
    store.switchMode = .both;store.playhead=2.5;store.chooseAngle(a.id)
    #expect(store.document.sequence.multicamGroups[0].cuts.last?.angleID==a.id)
    #expect(store.document.sequence.multicamGroups[0].audioCuts?.last?.angleID==a.id)
    #expect(store.document.sequence.multicamGroups[0].masterAudioAssetID==master.id)
    let before=store.document;store.cameraAudioIDs.remove(b.id);store.playhead=3;store.chooseAngle(b.id)
    #expect(store.document==before)
    #expect(try ProjectDocument.decode(JSONEncoder().encode(before))==before)
}
@MainActor @Test func audioRangePassPreservesVideoCutsAndUndoesAsOneAction() {
    let(store,a,b,master)=switchingStore();let before=store.document
    store.switchMode = .audio;store.switchArmed=true;store.replaceSwitchRange=true;store.switchRangeStart=1;store.switchRangeEnd=3
    store.togglePlayback();store.playhead=1.5;store.chooseAngle(a.id);store.stopPlayback()
    let after=store.document,group=after.sequence.multicamGroups[0]
    #expect(group.cuts==before.sequence.multicamGroups[0].cuts)
    #expect(MulticamSwitching.selectedAudio(in:group,at:.init(value:1,timescale:1))==master.id)
    #expect(MulticamSwitching.selectedAudio(in:group,at:.init(value:3,timescale:2))==a.id)
    #expect(MulticamSwitching.selectedAudio(in:group,at:.init(value:3,timescale:1))==b.id)
    store.undo();#expect(store.document==before)
    store.redo();#expect(store.document==after)
}
