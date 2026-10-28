import Testing
@testable import LifeEditor

@MainActor @Test func firstEditUndoPreservesNewProjectIdentity(){
    let store=EditorStore(),original=store.document
    store.addTitle();let edited=store.document
    #expect(edited.id==original.id)
    store.undo();#expect(store.document==original)
    store.redo();#expect(store.document==edited)
}
