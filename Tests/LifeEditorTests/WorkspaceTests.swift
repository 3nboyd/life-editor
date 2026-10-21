import Testing
import AppKit
import SwiftUI
import LifeCore
@testable import LifeEditor

@MainActor @Test func workspaceRendersAtPracticalWindowSize() throws {
    _ = NSApplication.shared
    let store=EditorStore()
    let host=NSHostingView(rootView:WorkspaceView(store:store).preferredColorScheme(.dark))
    host.frame=NSRect(x:0,y:0,width:1280,height:800)
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width<=1280)
    #expect(host.fittingSize.height<=800)
    let bitmap=try #require(host.bitmapImageRepForCachingDisplay(in:host.bounds))
    host.cacheDisplay(in:host.bounds,to:bitmap)
    let directory=URL(fileURLWithPath:ProcessInfo.processInfo.environment["LIFE_UI_ARTIFACTS"] ?? "/tmp/life-editor-ui-checks",isDirectory:true)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    try #require(bitmap.representation(using:.png,properties:[:])).write(to:directory.appendingPathComponent("workspace-1280x800.png"))
    #expect(bitmap.pixelsWide>=1280)
}

@MainActor @Test func invalidNumericClipStartDoesNotChangeDocument() {
    let store=EditorStore()
    let before=store.document
    store.setClipStart(1e15)
    #expect(store.document==before)
    #expect(store.error != nil)
    store.error=nil
    store.setClipStart(.infinity)
    #expect(store.document==before)
    #expect(store.error != nil)
}

@MainActor @Test func audioInspectorFitsAndSettingsUndoExactly() throws {
    _ = NSApplication.shared
    let store=EditorStore()
    let asset=MediaAsset(url:URL(fileURLWithPath:"/tmp/life-editor-ui-music.wav"),kind:.audio,duration:.init(value:4,timescale:1))
    let clip=Clip(name:"Music",assetID:asset.id,start:.zero,duration:.init(value:4,timescale:1))
    var project=ProjectDocument()
    project.assets=[asset]
    project.sequence.tracks=[Track(name:"Audio",kind:.audio,clips:[clip])]
    store.replace(project);store.selection=clip.id;store.panel = .audio
    let before=store.document
    store.editAudio{$0.gainDB=6;$0.pan = -0.5;$0.limiterEnabled=true}
    #expect(store.selectedClip?.audio?.gainDB==6)
    store.undo()
    #expect(store.document==before)
    let host=NSHostingView(rootView:WorkspaceView(store:store).preferredColorScheme(.dark))
    host.frame=NSRect(x:0,y:0,width:1280,height:800);host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width<=1280)
    #expect(host.fittingSize.height<=800)
    let bitmap=try #require(host.bitmapImageRepForCachingDisplay(in:host.bounds))
    host.cacheDisplay(in:host.bounds,to:bitmap)
    let url=URL(fileURLWithPath:"/tmp/life-editor-ui-checks/audio-1280x800.png")
    try #require(bitmap.representation(using:.png,properties:[:])).write(to:url)
}

@MainActor @Test func duplicateProjectRetainsEditsWithIndependentIdentity() {
    let store=EditorStore()
    var document=ProjectDocument(name:"Practice")
    document.sequence.tracks=[Track(name:"Title",kind:.title,clips:[Clip(duration:.init(value:3,timescale:1),title:.init(text:"Keep this"))])]
    store.replace(document)
    let original=store.document
    store.duplicateProject()
    #expect(store.document.id != original.id)
    #expect(store.document.name=="Practice Copy")
    #expect(store.document.sequence==original.sequence)
    #expect(store.dirty)
    #expect(!store.canUndo)
}

@MainActor @Test func armedRangePassIsOneUndoAndPreservesOutsideDecisions() throws {
    let store=EditorStore()
    let duration=RationalTime(value:4,timescale:1)
    let a=MediaAsset(url:URL(fileURLWithPath:"/tmp/life-camera-a.mov"),kind:.video,duration:duration)
    let b=MediaAsset(url:URL(fileURLWithPath:"/tmp/life-camera-b.mov"),kind:.video,duration:duration)
    let group=MulticamGroup(angleAssetIDs:[a.id,b.id],masterAudioAssetID:a.id,cuts:[.init(time:.zero,angleID:a.id),.init(time:.init(value:2,timescale:1),angleID:b.id)])
    let document=ProjectDocument(sequence:Sequence(tracks:[Track(name:"A",kind:.video,clips:[Clip(assetID:a.id,duration:duration)]),Track(name:"B",kind:.video,clips:[Clip(assetID:b.id,duration:duration)])],multicamGroups:[group]),assets:[a,b])
    store.replace(document);let before=store.document
    store.switchArmed=true;store.replaceSwitchRange=true;store.switchRangeStart=1;store.switchRangeEnd=3
    store.togglePlayback()
    #expect(store.playing)
    #expect(store.document.sequence.multicamGroups[0].cuts.map(\.time)==[.zero,.init(value:1,timescale:1),.init(value:3,timescale:1)])
    store.playhead=1.5;store.chooseAngle(b.id);store.stopPlayback()
    let after=store.document
    #expect(after.sequence.multicamGroups[0].cuts.last?.angleID==b.id)
    #expect(after.sequence.multicamGroups[0].masterAudioAssetID==a.id)
    #expect(try ProjectDocument.decode(JSONEncoder().encode(after))==after)
    store.undo();#expect(store.document==before)
    store.redo();#expect(store.document==after)
}
