import Testing
import Foundation
import LifeCore
@testable import LifeEditor

@MainActor @Test func placementPreviewCannotOverwriteInterveningEditsAndCommitsOneExactSnapshot() throws {
    let store=EditorStore()
    let clip=Clip(duration:.init(value:2,timescale:1),title:.init(text:"Source"))
    let document=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Titles",kind:.title,clips:[clip])]))
    store.replace(document);store.selection=clip.id
    let before=store.document
    store.previewPlacement(.insertCopies(clipIDs:[clip.id],at:.init(value:1,timescale:1)),title:"Insert")
    let proposal=try #require(store.placementProposal)
    #expect(store.document==before)
    #expect(store.timelineDocument==proposal.document)
    #expect(store.timelineDocument.sequence.tracks[0].clips.count==3)
    store.deleteSelection();#expect(store.document==before);#expect(store.selection==clip.id)
    store.error=nil;store.commitPlacement()
    #expect(store.document==proposal.document)
    #expect(store.placementProposal==nil)
    store.undo();#expect(store.document==before)
    store.redo();#expect(store.document==proposal.document)
    store.undo();store.selection=clip.id
    store.previewPlacement(.overwriteCopies(clipIDs:[clip.id],at:.init(value:1,timescale:1)),title:"Overwrite")
    store.document.name="Intervening external state"
    let changed=store.document
    store.commitPlacement()
    #expect(store.document==changed)
    #expect(store.placementProposal==nil && store.error != nil)
}
