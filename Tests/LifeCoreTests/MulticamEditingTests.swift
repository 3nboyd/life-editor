import Testing
import Foundation
@testable import LifeCore

@Test func rangePassPreservesOutsideCutsAndRestoresBoundary() throws {
    let a=UUID(),b=UUID(),audio=UUID()
    func t(_ n:Int64)->RationalTime{.init(value:n,timescale:1)}
    let original=MulticamGroup(angleAssetIDs:[a,b],masterAudioAssetID:audio,cuts:[.init(time:t(0),angleID:a),.init(time:t(3),angleID:b),.init(time:t(7),angleID:a),.init(time:t(10),angleID:b)])
    let edited=try MulticamEditing.replacingCuts(in:original,from:t(2),to:t(8),with:[.init(time:t(4),angleID:b)])
    #expect(edited.cuts.map(\.time)==[t(0),t(2),t(4),t(8),t(10)])
    #expect(edited.cuts.map(\.angleID)==[a,a,b,a,b])
    #expect(edited.masterAudioAssetID==audio)
    #expect(original.cuts.count==4)
    #expect(throws:DocumentError.self){try MulticamEditing.replacingCuts(in:original,from:t(2),to:t(8),with:[.init(time:t(8),angleID:b)])}
}
