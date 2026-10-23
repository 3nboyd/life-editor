import AppKit
import Testing
import LifeCore
@testable import LifeEditor

@MainActor @Test func camcorderDateEditsUndoAndInvalidClipboardContextIsAtomic()throws {
    let asset=MediaAsset(url:URL(fileURLWithPath:"/original.mov"),kind:.video,duration:.init(value:5,timescale:1))
    let effect=NativeEffectRegistry.make("life.filter.VHS")
    let clip=Clip(assetID:asset.id,duration:.init(value:3,timescale:1),effects:[effect])
    let store=EditorStore();store.replace(ProjectDocument(sequence:Sequence(tracks:[Track(name:"Video",kind:.video,clips:[clip])]),assets:[asset]));store.selection=clip.id
    let before=store.document
    let date=try #require(CamcorderDateOverlay.parse("2024-02-29T12:34:56+02:00"))
    store.editSelected{$0.effects?[0].camcorderDate=date}
    let after=store.document
    #expect(store.selectedClip?.effects?[0].camcorderDate==date)
    store.undo();#expect(store.document==before);store.redo();#expect(store.document==after)
    let board=NSPasteboard(name:.init("life-date-"+UUID().uuidString));defer{board.releaseGlobally()}
    store.copyEffectSettings(to:board)
    store.addAdjustmentLayer();let adjustment=store.document
    store.pasteEffectSettings(from:board)
    #expect(store.document==adjustment)
    #expect(store.error?.contains("Camcorder dates") == true)
    #expect(try ProjectDocument.decode(after.encoded())==after)
}
