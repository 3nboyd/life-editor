import Testing
import AppKit
import LifeCore
@testable import LifeEditor

@MainActor @Test func trackSoloIsUndoableAndCannotArmNonAudioTracks() {
    let store=EditorStore(),audio=Track(name:"Music",kind:.audio),video=Track(name:"Camera",kind:.video),title=Track(name:"Text",kind:.title)
    let original=ProjectDocument(sequence:.init(tracks:[audio,video,title]))
    store.replace(original);store.toggleTrack(audio.id,property:"solo")
    let soloed=store.document;#expect(soloed.sequence.tracks[0].isSoloed)
    store.toggleTrack(video.id,property:"solo");#expect(store.document.sequence.tracks[1].isSoloed)
    store.undo();#expect(store.document==soloed)
    store.undo();#expect(store.document==original)
    store.redo();#expect(store.document==soloed)
    store.toggleTrack(title.id,property:"solo");#expect(store.document==soloed)
    store.toggleTrack(audio.id,property:"mute");#expect(!store.document.sequence.isAudioAudible(on:store.document.sequence.tracks[0]))
}

@MainActor @Test func emptyTrackSoloRemainsAccessibleAndPointerOperable() throws {
    _ = NSApplication.shared
    let store=EditorStore(),track=Track(name:"Empty music",kind:.audio,isSoloed:true)
    store.replace(.init(sequence:.init(tracks:[track])))
    let canvas=TimelineCanvas(store:store),window=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:250),styleMask:[.titled],backing:.buffered,defer:false)
    window.contentView=canvas;canvas.frame=NSRect(x:0,y:0,width:800,height:250)
    canvas.refreshAccessibility()
    let button=try #require((canvas.accessibilityChildren() as? [NSAccessibilityElement])?.first{$0.accessibilityLabel()=="Unsolo Empty music"})
    #expect(button.accessibilityFrame().width>=30 && button.accessibilityFrame().height>=30)
    #expect(button.accessibilityPerformPress());#expect(!store.document.sequence.tracks[0].isSoloed)
    store.undo();#expect(store.document.sequence.tracks[0].isSoloed)
    let box=canvas.trackControlRect(3,row:0),point=canvas.convert(NSPoint(x:box.midX,y:box.midY),to:nil)
    let click=try #require(NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1))
    canvas.mouseDown(with:click);#expect(!store.document.sequence.tracks[0].isSoloed)
    store.undo();#expect(store.document.sequence.tracks[0].isSoloed)
    window.orderOut(nil)
}
