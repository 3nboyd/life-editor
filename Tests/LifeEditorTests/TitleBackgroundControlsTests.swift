import Testing
import AppKit
import SwiftUI
import LifeCore
@testable import LifeEditor

@MainActor @Test func titleBackgroundControlsPreserveLegacyUntilChangedAndGroupSliderUndo()throws {
    let store=EditorStore(),clip=Clip(duration:.init(value:2,timescale:1),title:.init(text:"Keep me",fontSize:40,style:.init(background:.black,cornerRadius:0.1)))
    let original=ProjectDocument(sequence:.init(tracks:[.init(name:"Text",kind:.title,clips:[clip])]))
    store.replace(original);store.selection=clip.id
    let controls=TitleBackgroundControls(store:store)
    #expect(store.document==original)
    controls.update{$0.shape = .pill}
    let changed=store.document
    #expect(changed.sequence.tracks[0].clips[0].title?.style?.backgroundStyle?.padding==10)
    #expect(changed.sequence.tracks[0].clips[0].title?.style?.background == .black)
    store.undo();#expect(store.document==original);store.redo();#expect(store.document==changed)
    store.beginGesture();for value in [12.0,14,16]{controls.update{$0.padding=value}};store.endGesture()
    #expect(store.document.sequence.tracks[0].clips[0].title?.style?.backgroundStyle?.padding==16)
    store.undo();#expect(store.document==changed)
    controls.update{$0.shape = .none};#expect(store.document.sequence.tracks[0].clips[0].title?.style?.background == .black)
}

@MainActor @Test func titleBackgroundChoosingShapeCreatesVisibleFillAndNonePreservesIt(){
    let store=EditorStore(),clip=Clip(duration:.init(value:1,timescale:1),title:.init(text:"New title"))
    store.replace(ProjectDocument(sequence:.init(tracks:[.init(name:"Text",kind:.title,clips:[clip])])));store.selection=clip.id
    let controls=TitleBackgroundControls(store:store)
    controls.selectShape(.square)
    let fill=store.selectedClip?.title?.style?.background
    #expect((fill?.alpha ?? 0)>0);#expect(store.selectedClip?.title?.style?.backgroundStyle?.shape == .square)
    controls.selectShape(.none);#expect(store.selectedClip?.title?.style?.background==fill)
    controls.selectShape(.rounded);#expect(store.selectedClip?.title?.style?.background==fill)
}


@MainActor @Test func titleBackgroundExpandedControlsFitNarrowInspector()async throws {
    _ = NSApplication.shared
    let style=TitleStyle(background:.black,backgroundStyle:.init(shape:.speechBubble,padding:512,borderWidth:100,shadowColor:.black,shadowBlur:100,shadowOffsetX:512,shadowOffsetY:-512))
    let clip=Clip(duration:.init(value:1,timescale:1),title:.init(text:"Title",style:style)),store=EditorStore()
    store.replace(ProjectDocument(sequence:.init(tracks:[.init(name:"Title",kind:.title,clips:[clip])])));store.selection=clip.id
    let host=NSHostingView(rootView:TitleBackgroundControls(store:store,expanded:true,shadowExpanded:true).padding(12).background(Color(red:0.10,green:0.11,blue:0.12)).tint(Color(red:0.54,green:0.72,blue:0.69)).preferredColorScheme(.dark))
    host.appearance=NSAppearance(named:.darkAqua)
    host.frame=NSRect(x:0,y:0,width:248,height:800);host.layoutSubtreeIfNeeded()
    try await Task.sleep(for:.milliseconds(300));host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width<=248)
    #expect(host.fittingSize.height<=800)
    let bitmap=try #require(host.bitmapImageRepForCachingDisplay(in:host.bounds));host.cacheDisplay(in:host.bounds,to:bitmap)
    let directory=URL(fileURLWithPath:ProcessInfo.processInfo.environment["LIFE_UI_ARTIFACTS"] ?? "/tmp/life-editor-ui-checks",isDirectory:true)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    try #require(bitmap.representation(using:.png,properties:[:])).write(to:directory.appendingPathComponent("title-background-controls.png"))
    #expect(store.selectedClip?.title?.style==style)
}
