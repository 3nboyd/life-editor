import Foundation
import Testing
import LifeCore
@testable import LifeEditor

@MainActor @Test func textPresetButtonUsesOneUndoAndRetainsContentAndManualAnimation() throws {
    let store=EditorStore()
    let unrelated=EffectInstance(stableID:"life.adjust.exposure",parameters:["value":0.3])
    let clip=Clip(start:.init(value:2,timescale:1),duration:.init(value:3,timescale:1),title:.init(text:"My lyric line",fontSize:41,style:.init(fontName:"Georgia",x:0.3,y:0.4),animation:.init(kind:.slide,duration:0.7)),effects:[unrelated])
    let original=ProjectDocument(sequence:.init(tracks:[.init(name:"Lyrics",kind:.title,clips:[clip])]))
    store.replace(original);store.selection=clip.id
    let controls=TextPresetControls(store:store)
    controls.apply(.neon)
    let neon=store.document
    #expect(neon != original)
    #expect(neon.sequence.tracks[0].clips[0].title?.text==clip.title?.text)
    #expect(neon.sequence.tracks[0].clips[0].title?.fontSize==41)
    #expect(neon.sequence.tracks[0].clips[0].effects?.first==unrelated)
    store.undo();#expect(store.document==original)
    store.redo();#expect(store.document==neon)
    controls.apply(.typewriter)
    let typed=store.document.sequence.tracks[0].clips[0]
    #expect(typed.title?.style?.fontName=="Menlo")
    #expect(typed.title?.animation==clip.title?.animation)
    #expect(typed.effects?.last?.parameters["value"]==0)
    #expect(typed.effects?.last?.id==neon.sequence.tracks[0].clips[0].effects?.last?.id)
    store.editSelected{$0.effects?.append(EffectInstance(stableID:TextPresets.bloomID,parameters:["value":0.5]))}
    let duplicated=store.document
    controls.apply(.plain)
    #expect(store.document==duplicated)
    #expect(store.error?.contains("one Bloom")==true)
}
