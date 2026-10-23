import Testing
import LifeCore
@MainActor @Test func tonalAdjustmentRegistryDefaultsRangesPersistenceAndUndo()throws{
    let ids=["life.adjust.whites","life.adjust.blackPoint","life.adjust.brilliance"]
    var document=try AdjustmentLayers.adding(at:.zero,duration:.init(value:2,timescale:1),in:ProjectDocument())
    for id in ids{
        let definition=try #require(NativeEffectRegistry.definition(for:id)),parameter=try #require(definition.parameters.first)
        #expect(parameter.range == -1...1 && parameter.defaultValue==0 && parameter.supportsAnimation)
        #expect(NativeEffectRegistry.make(id).parameters["value"]==0)
        var effect=NativeEffectRegistry.make(id);effect.parameters["value"] = -0.5;effect.strength=0.7;document.sequence.tracks[0].clips[0].effects?.append(effect)
    }
    let editor=ProjectEditor(),initial=editor.document;try editor.perform(.replace(document))
    #expect(try ProjectDocument.decode(editor.document.encoded())==document)
    editor.undo();#expect(editor.document==initial);editor.redo();#expect(editor.document==document)
    var invalid=document;invalid.sequence.tracks[0].clips[0].effects?[0].parameters["value"]=1.01
    #expect(throws:DocumentError.self){try invalid.validate()}
}
