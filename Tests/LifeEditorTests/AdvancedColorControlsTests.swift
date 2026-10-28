import Testing
import AppKit
import SwiftUI
import LifeCore
@testable import LifeEditor

@MainActor @Test func advancedColorControlsGroupUndoAndProtectLevelOrder()throws {
    let store=EditorStore(),clip=Clip(duration:.init(value:2,timescale:1),title:.init(text:"Color"))
    let original=ProjectDocument(sequence:.init(tracks:[.init(name:"Title",kind:.title,clips:[clip])]))
    store.replace(original);store.selection=clip.id;let controls=AdvancedColorControls(store:store)
    store.beginGesture();for number in [0.6,0.7,0.8]{controls.setParameter("life.adjust.curves","red2",number)};store.endGesture()
    #expect(controls.value("life.adjust.curves","red2")==0.8);store.undo();#expect(store.document==original);store.redo()
    controls.setParameter("life.adjust.levels","black",0.9);controls.setParameter("life.adjust.levels","white",0.2)
    #expect(controls.value("life.adjust.levels","white")>controls.value("life.adjust.levels","black"));try store.document.validate()
    let before=store.document;controls.setParameter("life.adjust.hsl","redHue",.nan);#expect(store.document==before)
    controls.setParameter("life.adjust.hsl","redHue",30);#expect(controls.value("life.adjust.hsl","redHue")==30)
    controls.reset("life.adjust.hsl");#expect(controls.value("life.adjust.hsl","redHue")==0)
    store.undo();#expect(controls.value("life.adjust.hsl","redHue")==30)
}

@MainActor @Test func advancedColorControlsFitNarrowInspectorWithoutChangingDocument()async throws {
    _ = NSApplication.shared
    let store=EditorStore(),clip=Clip(duration:.init(value:1,timescale:1),title:.init(text:"Color"))
    let original=ProjectDocument(sequence:.init(tracks:[.init(name:"Title",kind:.title,clips:[clip])]))
    store.replace(original);store.selection=clip.id
    for section in 0...2 {
        let host=NSHostingView(rootView:AdvancedColorControls(store:store,expanded:true,section:section).padding(12).preferredColorScheme(.dark))
        host.frame=NSRect(x:0,y:0,width:248,height:800);host.layoutSubtreeIfNeeded()
        try await Task.sleep(for:.milliseconds(100));host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width<=248);#expect(host.fittingSize.height<=800)
        #expect(store.document==original)
    }
}
