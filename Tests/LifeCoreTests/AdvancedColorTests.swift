import Foundation
import Testing
@testable import LifeCore

@Test func advancedColorDefaultsPersistenceAndValidation()throws {
    let effects=NativeEffectRegistry.advancedAdjustments.map{NativeEffectRegistry.make($0.stableID)}
    #expect(effects.count==3);#expect(effects.allSatisfy{NativeEffectRegistry.definition(for:$0.stableID)?.supportsAnimation==false})
    #expect(AdvancedColor.evaluateCurve(0.375,values:[0,0.25,0.5,0.75,1])==0.375)
    #expect(AdvancedColor.evaluateCurve(0.375,values:[0,0.5,0.75,0.9,1])==0.625)
    var clip=Clip(duration:.init(value:2,timescale:1),title:.init(text:"Color"));clip.effects=effects
    let document=ProjectDocument(sequence:.init(tracks:[.init(name:"Text",kind:.title,clips:[clip])]))
    try document.validate();#expect(try ProjectDocument.decode(document.encoded())==document)
    var invalid=document;invalid.sequence.tracks[0].clips[0].effects?[1].parameters["black"]=0.9;invalid.sequence.tracks[0].clips[0].effects?[1].parameters["white"]=0.2
    #expect(throws:DocumentError.invalidTiming){try invalid.validate()}
    invalid=document;invalid.sequence.tracks[0].clips[0].effects?[0].parameters["red2"]=1.1
    #expect(throws:DocumentError.invalidTiming){try invalid.validate()}
    var legacy=document;legacy.version=8;legacy.sequence.tracks[0].clips[0].effects=nil
    let migrated=try ProjectDocument.decode(JSONEncoder().encode(legacy));#expect(migrated.version==9);#expect(migrated.sequence.tracks[0].clips[0].effects==nil)
    #expect(throws:DocumentError.unsupportedVersion(10)){try ProjectDocument.decode(Data(#"{"version":10}"#.utf8))}
}
