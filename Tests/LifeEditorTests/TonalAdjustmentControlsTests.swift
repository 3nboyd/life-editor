import AppKit
import Testing
import LifeCore
@testable import LifeEditor
@MainActor @Test func tonalAdjustmentSlidersBypassResetClipboardAndUndoUseExistingControls()throws{
    let store=EditorStore();store.addAdjustmentLayer();let browser=EffectBrowser(store:store),ids=["life.adjust.whites","life.adjust.blackPoint","life.adjust.brilliance"]
    let baseline=store.document;store.beginGesture()
    for id in ids{browser.setAdjustment(id,0.6)}
    store.endGesture();let changed=store.document
    #expect(store.selectedClip?.effects?.count==3);store.undo();#expect(store.document==baseline);store.redo();#expect(store.document==changed)
    let effect=try #require(store.selectedClip?.effects?.first);store.setEffectEnabled(id:effect.id,enabled:false)
    let clipboard=NSPasteboard(name:.init(UUID().uuidString));defer{clipboard.releaseGlobally()}
    store.copyEffectSettings(to:clipboard);let copied=try #require(store.selectedClip?.effects)
    store.resetAdjustments();#expect(store.selectedClip?.effects?.isEmpty==true)
    let beforePaste=store.document;store.pasteEffectSettings(from:clipboard)
    let pasted=try #require(store.selectedClip?.effects);#expect(pasted.map(\.stableID)==copied.map(\.stableID));#expect(pasted.map(\.parameters)==copied.map(\.parameters));#expect(pasted.map(\.isEnabled)==copied.map(\.isEnabled))
    store.undo();#expect(store.document==beforePaste)
}
