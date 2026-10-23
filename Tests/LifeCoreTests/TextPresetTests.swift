import Foundation
import Testing
@testable import LifeCore

@MainActor @Test func textPresetsPreserveContentClocksAndCanonicalEffectIdentity() throws {
    let unrelated=EffectInstance(stableID:"life.adjust.exposure",parameters:["value":0.5],seed:42)
    var bloom=EffectInstance(stableID:TextPresets.bloomID,parameters:["value":0.3,"retained":0.2],strength:0.6,seed:73,isEnabled:false)
    let clip=Clip(name:"Lyrics",start:.init(value:2,timescale:1),duration:.init(value:3,timescale:1),sourceStart:.init(value:1,timescale:1),speed:0.5,title:.init(text:"Keep these words",fontSize:37,style:.init(x:0.2,y:0.3,cornerRadius:0.04),animation:.init(kind:.bounce,duration:1)),effects:[unrelated,bloom])
    let neon=try TextPresets.applying(.neon,to:clip)
    #expect(neon.title?.text==clip.title?.text && neon.title?.fontSize==37 && neon.title?.animation==clip.title?.animation)
    #expect(neon.start==clip.start && neon.duration==clip.duration && neon.sourceStart==clip.sourceStart && neon.speed==clip.speed)
    #expect(neon.effects?.first==unrelated);#expect(neon.effects?.last?.id==bloom.id)
    #expect(neon.effects?.last?.parameters["value"]==0.8 && neon.effects?.last?.isEnabled==true)
    #expect(neon.title?.style?.x==0.2 && neon.title?.style?.y==0.3 && neon.title?.style?.cornerRadius==0.04)
    #expect(try TextPresets.applying(.neon,to:neon)==neon)
    for family in TextFamily.allCases {
        let updated=try TextPresets.applying(family,to:neon)
        #expect(updated.effects?.first==unrelated);#expect(updated.effects?.count==2);#expect(updated.effects?.last?.id==bloom.id)
        #expect(updated.effects?.last?.parameters["retained"]==0.2 && updated.effects?.last?.seed==73)
        #expect(updated.effects?.last?.parameters["value"]==(family == .neon ? 0.8:0))
        #expect(updated.title?.animation==clip.title?.animation)
        let original=ProjectDocument(sequence:.init(tracks:[.init(name:"Text",kind:.title,clips:[clip])]))
        var next=original;next.sequence.tracks[0].clips=[updated]
        let editor=ProjectEditor(document:original);try editor.perform(.replace(next));editor.undo();#expect(editor.document==original);editor.redo();#expect(editor.document==next)
        #expect(try ProjectDocument.decode(next.encoded())==next)
    }
    bloom.id=UUID();var duplicated=clip;duplicated.effects?.append(bloom)
    #expect(throws:TextPresetError.self){try TextPresets.applying(.neon,to:duplicated)}
    let plain=try TextPresets.applying(.plain,to:Clip(duration:.init(value:1,timescale:1),title:.init(text:"A")))
    #expect(plain.effects==nil)
}
