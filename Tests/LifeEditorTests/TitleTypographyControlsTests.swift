import Testing
import LifeCore
@testable import LifeEditor

@MainActor @Test func titleTypographyControlsEditAndUndoOneSpacingGesture(){
    let store=EditorStore(),clip=Clip(duration:.init(value:2,timescale:1),title:.init(text:"Two\nLines",style:.init(background:.black)))
    let original=ProjectDocument(sequence:.init(tracks:[.init(name:"Text",kind:.title,clips:[clip])]))
    store.replace(original);store.selection=clip.id
    let controls=TitleTypographyControls(store:store)
    #expect(store.document==original)
    controls.update{$0.alignment = .left};let aligned=store.document
    store.beginGesture();for value in [2.0,4,7]{controls.update{$0.letterSpacing=value}};store.endGesture()
    #expect(store.selectedClip?.title?.style?.typography?.letterSpacing==7)
    store.undo();#expect(store.document==aligned)
    store.undo();#expect(store.document==original)
    store.redo();#expect(store.document==aligned)
    controls.update{$0.lineSpacing = .nan};#expect(store.document==aligned)
    #expect(store.selectedClip?.title?.style?.background == .black)
}
