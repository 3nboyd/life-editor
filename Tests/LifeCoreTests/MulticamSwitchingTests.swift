import Foundation
import Testing
@testable import LifeCore

@Test func independentMulticamSwitchesQuantizeAndPreserveIDsAndRangeResume() throws {
    let a=UUID(),b=UUID(),master=UUID();let half=RationalTime(value:1,timescale:2)
    let group=MulticamGroup(angleAssetIDs:[a,b],masterAudioAssetID:master)
    let audio=try MulticamSwitching.applying(angleID:b,at:.init(value:501,timescale:1000),mode:.audio,to:group,frameRate:.init(),availableAudioAssetIDs:[a,b])
    #expect(audio.cuts.isEmpty);#expect(audio.audioCuts?.first?.time==half)
    #expect(MulticamSwitching.selectedAudio(in:audio,at:.zero)==master)
    #expect(MulticamSwitching.selectedAudio(in:audio,at:half)==b)
    let noOp=try MulticamSwitching.applying(angleID:b,at:.init(value:3,timescale:4),mode:.audio,to:audio,frameRate:.init(),availableAudioAssetIDs:[a,b])
    #expect(noOp==audio)
    #expect(throws:DocumentError.sourceBoundary){try MulticamSwitching.applying(angleID:a,at:half,mode:.both,to:group,frameRate:.init(),availableAudioAssetIDs:[])}
    let replaced=try MulticamSwitching.replacingAudioCuts(in:audio,from:.init(value:1,timescale:4),to:.init(value:3,timescale:4),with:[.init(time:half,angleID:a)])
    #expect(MulticamSwitching.selectedAudio(in:replaced,at:.init(value:3,timescale:4))==b)
    #expect(MulticamSwitching.selectedAudio(in:replaced,at:.init(value:1,timescale:4))==master)
    let legacy=Data("{\"time\":{\"value\":1,\"timescale\":2},\"angleID\":\"\(a.uuidString)\"}".utf8)
    let first=try JSONDecoder().decode(MulticamCut.self,from:legacy)
    #expect(try JSONDecoder().decode(MulticamCut.self,from:legacy).id==first.id)
    #expect(try JSONDecoder().decode(MulticamCut.self,from:JSONEncoder().encode(first))==first)
    let silence=try MulticamSwitching.replacingAudioCuts(in:.init(angleAssetIDs:[a]),from:.zero,to:half,with:[.init(time:.zero,angleID:a)])
    #expect(MulticamSwitching.selectedAudio(in:silence,at:half)==nil)
}
