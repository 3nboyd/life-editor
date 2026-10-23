import Testing
import Foundation
@testable import LifeCore

@Test func camcorderDatesRequireExplicitStrictTimezoneAndSurviveRoundtrip()throws {
    #expect(CamcorderDateOverlay.parse("")==nil)
    #expect(CamcorderDateOverlay.parse("2000-01-01T00:00:00."+String(repeating:"1",count:100000)+"Z")==nil)
    #expect(CamcorderDateOverlay.parse("1899-12-31T23:59:59Z")==nil)
    #expect(CamcorderDateOverlay.parse("2102-01-01T00:00:00Z")==nil)
    #expect(CamcorderDateOverlay.parse("2024-02-30T12:00:00Z")==nil)
    #expect(CamcorderDateOverlay.parse("2024-01-01T12:00:00")==nil)
    #expect(CamcorderDateOverlay.parse("2024-01-01T12:00:00+14:01")==nil)
    var date=try #require(CamcorderDateOverlay.parse("2024-02-29T23:59:59.125-05:00"))
    #expect(date.text(at:.init(value:1,timescale:1))=="2024-03-01 00:00:00")
    #expect(CamcorderDateOverlay.parse(date.entryText)?.sourceZeroUnixSeconds==date.sourceZeroUnixSeconds)
    let precise=try #require(CamcorderDateOverlay.parse("2024-02-29T23:59:59.123456789-05:00"))
    #expect(CamcorderDateOverlay.parse(precise.entryText)?.sourceZeroUnixSeconds==precise.sourceZeroUnixSeconds)
    date.utcOffsetSeconds=Int.min
    #expect(!date.isValid)
    let encoded=try JSONEncoder().encode(date)
    #expect(!(try JSONDecoder().decode(CamcorderDateOverlay.self,from:encoded)).isValid)
    let legacy=Data(#"{"id":"00000000-0000-0000-0000-000000000001","stableID":"life.filter.VHS","parameters":{},"strength":1,"seed":0,"isEnabled":true}"#.utf8)
    #expect(try JSONDecoder().decode(EffectInstance.self,from:legacy).camcorderDate==nil)
}

@MainActor @Test func camcorderDatesPersistUndoAndRejectUnsupportedContexts()throws {
    let asset=MediaAsset(url:URL(fileURLWithPath:"/original.mov"),kind:.video,duration:.init(value:10,timescale:1))
    var effect=NativeEffectRegistry.make("life.filter.VHS");effect.camcorderDate=CamcorderDateOverlay.parse("2000-01-01T00:00:00Z")
    let clip=Clip(assetID:asset.id,duration:.init(value:3,timescale:1),effects:[effect])
    let document=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Video",kind:.video,clips:[clip])]),assets:[asset])
    try document.validate()
    #expect(try ProjectDocument.decode(document.encoded())==document)
    var bad=document;bad.sequence.tracks[0].clips[0].effects?[0].stableID="life.filter.clean"
    #expect(throws:CamcorderDateError.self){try bad.validate()}
    bad=document;bad.sequence.tracks[0].kind = .adjustment
    #expect(throws:CamcorderDateError.self){try bad.validate()}
    let editor=ProjectEditor(document:document)
    try editor.perform(.split(clipID:clip.id,at:.init(value:1,timescale:1)))
    let split=editor.document.sequence.tracks[0].clips
    #expect(split[1].effects?[0].camcorderDate==effect.camcorderDate)
    #expect(split[1].sourceTime(at:.init(value:2,timescale:1)) == .init(value:2,timescale:1))
    editor.undo();#expect(editor.document==document)
}
