import AppKit
import Foundation
import Testing
import LifeCore
@testable import LifeEditor

@MainActor struct AdjustmentControlsTests {
    @Test func addingAdjustmentSelectsTopLayerWithOneUndoAndContextualOpacity() throws {
        let store=EditorStore(),source=Clip(duration:.init(value:10,timescale:1),title:.init(text:"Base"))
        let original=ProjectDocument(sequence:.init(tracks:[.init(name:"Video",kind:.title,clips:[source])]))
        store.replace(original);store.playhead=2;store.selectedTransition=UUID();store.addAdjustmentLayer()
        #expect(store.document.sequence.tracks.count==2)
        let added=try #require(store.selectedClip)
        #expect(added.start == .init(value:2,timescale:1));#expect(added.duration == .init(value:8,timescale:1))
        #expect(store.selectedIsAdjustment && store.selectedUsesOpacity && store.automationLane == .opacity)
        #expect(store.panel == .effects && store.selectedTransition == nil);#expect(store.document.sequence.tracks[0]==original.sequence.tracks[0])
        let after=store.document
        store.selection=source.id;store.selectedIDs=[source.id,added.id]
        #expect(!store.selectedIsAdjustment && store.selectionIncludesAdjustment)
        store.selection=added.id
        store.undo();#expect(store.document==original);store.redo();#expect(store.document==after)
        store.selection=added.id;store.setAdjustmentDuration(4)
        #expect(store.selectedClip?.duration == .init(value:4,timescale:1))
        store.setClipStart(3);#expect(store.selectedClip?.start == .init(value:3,timescale:1))
        #expect(store.document.sequence.settings==original.sequence.settings)
        let empty=EditorStore();empty.addAdjustmentLayer()
        #expect(empty.selectedClip?.duration == .init(value:3,timescale:1))
    }
    @Test func adjustmentEffectsResetBypassAndPrivateClipboardPreserveTimingAndOpacity() throws {
        let store=EditorStore();store.addAdjustmentLayer();let clip=try #require(store.selectedClip)
        let browser=EffectBrowser(store:store)
        browser.setAdjustment("life.adjust.exposure",0.7);browser.applyPreset("life.filter.cool")
        let effect=try #require(store.selectedClip?.effects?.first)
        store.setEffectEnabled(id:effect.id,enabled:false)
        #expect(store.selectedClip?.effects?.first?.isEnabled==false)
        let clipboard=NSPasteboard(name:.init("life-test-effects-\(UUID())"))
        defer{clipboard.releaseGlobally()}
        store.copyEffectSettings(to:clipboard)
        let sourceEffects=try #require(store.selectedClip?.effects)
        store.setAutomationBase(0.5);let opacity=try #require(store.selectedClip?.opacity)
        store.resetAdjustments()
        #expect(store.selectedClip?.effects?.allSatisfy{$0.stableID.hasPrefix("life.filter.")}==true)
        let beforePaste=store.document
        store.pasteEffectSettings(from:clipboard)
        let pasted=try #require(store.selectedClip?.effects)
        #expect(pasted.map(\.stableID)==sourceEffects.map(\.stableID))
        #expect(pasted.map(\.parameters)==sourceEffects.map(\.parameters))
        #expect(pasted.map(\.isEnabled)==sourceEffects.map(\.isEnabled))
        #expect(Set(pasted.map(\.id)).isDisjoint(with:Set(sourceEffects.map(\.id))))
        #expect(store.selectedClip?.opacity==opacity && store.selectedClip?.duration==clip.duration)
        #expect(store.selectedClip?.start==clip.start)
        store.undo();#expect(store.document==beforePaste)
        #expect(try ProjectDocument.decode(store.document.encoded())==store.document)
    }
}
