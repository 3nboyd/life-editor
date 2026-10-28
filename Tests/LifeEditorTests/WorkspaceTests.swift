import Testing
import AppKit
import SwiftUI
import AVKit
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

@MainActor @Test func markerControlsMapSourceTimingAndUndoAnnotations() throws {
    let store=EditorStore()
    let asset=MediaAsset(url:URL(fileURLWithPath:"/tmp/life-marker.wav"),kind:.audio,duration:.init(value:20,timescale:1))
    let clip=Clip(assetID:asset.id,start:.init(value:2,timescale:1),duration:.init(value:4,timescale:1),sourceStart:.init(value:3,timescale:1),speed:2)
    var document=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Music",kind:.audio,clips:[clip])]),assets:[asset])
    let marker=Marker(time:.init(value:3,timescale:1),duration:.init(value:1,timescale:1),name:"Verse",note:"Keep the pickup")
    document.sequence.markers=[marker]
    store.replace(document);store.selection=clip.id
    store.anchorMarker(marker.id,toSelected:true)
    #expect(store.document.sequence.markers[0].clipID==clip.id)
    #expect(store.document.sequence.markers[0].time == .init(value:5,timescale:1))
    #expect(store.document.sequence.markers[0].duration == .init(value:2,timescale:1))
    let anchored=store.document
    store.setMarkerTiming(marker.id,start:3.5,duration:0.5)
    #expect(MarkerResolver.sequenceRange(store.document.sequence.markers[0],in:store.document)?.start == .init(value:7,timescale:2))
    store.undo();#expect(store.document==anchored)
    store.anchorMarker(marker.id,toSelected:false)
    #expect(store.document.sequence.markers[0].time==marker.time)
    #expect(store.document.sequence.markers[0].note==marker.note)
    #expect(try ProjectDocument.decode(JSONEncoder().encode(store.document))==store.document)
}

@MainActor @Test func debouncedAutosaveWritesLatestCommittedEditAndProtectsNewerFormats() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("life-autosave-"+UUID().uuidString,isDirectory:true)
    defer{try? FileManager.default.removeItem(at:root)}
    let url=root.appendingPathComponent("Autosave.lifeedit",isDirectory:true)
    let clip=Clip(duration:.init(value:2,timescale:1),title:.init(text:"First"))
    let document=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Title",kind:.title,clips:[clip])]))
    try ProjectPackage.write(document,to:url)
    let store=EditorStore();store.openProject(url);store.selection=clip.id
    store.editSelected{$0.title?.text="Second"}
    store.editSelected{$0.title?.text="Latest"}
    let clock=ContinuousClock();let saveDeadline=clock.now.advanced(by:.seconds(15))
    while store.dirty && clock.now<saveDeadline{try await Task.sleep(for:.milliseconds(50))}
    try #require(!store.dirty,"Autosave did not complete before its bounded deadline")
    #expect(try ProjectPackage.read(from:url)==store.document)
    #expect(store.selectedClip?.title?.text=="Latest")
    #expect(!store.dirty)
    let data=try JSONEncoder().encode(store.document)
    var json=try #require(JSONSerialization.jsonObject(with:data) as? [String:Any]);json["version"]=999
    let newer=try JSONSerialization.data(withJSONObject:json,options:.sortedKeys)
    let projectURL=url.appendingPathComponent(ProjectPackage.projectFilename)
    try newer.write(to:projectURL,options:.atomic)
    store.editSelected{$0.title?.text="Must not overwrite"}
    let refusalDeadline=clock.now.advanced(by:.seconds(15))
    while store.autosaveError==nil && clock.now<refusalDeadline{try await Task.sleep(for:.milliseconds(50))}
    #expect(try Data(contentsOf:projectURL)==newer)
    #expect(store.dirty)
    #expect(store.autosaveError?.contains("unsupported") == true)
}

@MainActor @Test func markerAnchoringRejectsUnrepresentableIntermediateWithoutCrashing() throws {
    let store=EditorStore()
    let asset=MediaAsset(url:URL(fileURLWithPath:"/tmp/life-marker-rational.wav"),kind:.audio,duration:.init(value:80022,timescale:1))
    let clip=Clip(assetID:asset.id,duration:.init(value:20,timescale:1),sourceStart:.init(value:80000*999999937+1,timescale:999999937),speed:1.05)
    let marker=Marker(time:.init(value:1,timescale:48000),name:"Sample")
    let document=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Music",kind:.audio,clips:[clip])],markers:[marker]),assets:[asset])
    try document.validate()
    store.replace(document);store.selection=clip.id
    let before=store.document
    store.anchorMarker(marker.id,toSelected:true)
    #expect(store.document==before)
    #expect(store.error != nil)
}

@MainActor @Test func frameSteppingRetainsExactNTSCClockAcrossLongSequences() {
    let store=EditorStore(),rate=FrameRate(numerator:30000,denominator:1001)
    store.document.sequence.settings.frameRate=rate
    store.document.sequence.tracks=[Track(name:"Long title",kind:.title,clips:[Clip(duration:.init(value:3600,timescale:1),title:.init(text:"Clock"))])]
    for _ in 0..<3000{store.step(1)}
    #expect(store.playheadTime==rate.time(forFrame:3000))
    for _ in 0..<3000{store.step(-1)}
    #expect(store.playheadTime == .zero)
}

@MainActor @Test func placementPreviewFitsPracticalWindowWithSelectedClip() throws {
    _ = NSApplication.shared
    let store=EditorStore(),clip=Clip(duration:.init(value:2,timescale:1),title:.init(text:"Verse"))
    store.replace(ProjectDocument(sequence:Sequence(tracks:[Track(name:"Titles",kind:.title,clips:[clip])])))
    store.selection=clip.id;store.selectedIDs=[clip.id]
    store.previewPlacement(.insertCopies(clipIDs:[clip.id],at:.init(value:1,timescale:1)),title:"Insert")
    let host=NSHostingView(rootView:WorkspaceView(store:store).preferredColorScheme(.dark))
    host.frame=NSRect(x:0,y:0,width:1280,height:800);host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width<=1280);#expect(host.fittingSize.height<=800)
    let bitmap=try #require(host.bitmapImageRepForCachingDisplay(in:host.bounds))
    host.cacheDisplay(in:host.bounds,to:bitmap)
    let directory=URL(fileURLWithPath:ProcessInfo.processInfo.environment["LIFE_UI_ARTIFACTS"] ?? "/tmp/life-editor-ui-checks",isDirectory:true)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    try #require(bitmap.representation(using:.png,properties:[:])).write(to:directory.appendingPathComponent("placement-1280x800.png"))
    store.cancelPlacement()
}

@MainActor @Test func multicamPreviewsSitBesideUnobscuredOutputAtPracticalWindowSize() throws {
    _ = NSApplication.shared
    let store=EditorStore(),duration=RationalTime(value:4,timescale:1)
    let assets=(1...4).map{MediaAsset(url:URL(fileURLWithPath:"/tmp/life-layout-camera-\($0).mov"),kind:.video,duration:duration)}
    let group=MulticamGroup(angleAssetIDs:assets.map(\.id),masterAudioAssetID:assets[0].id,cuts:[.init(time:.zero,angleID:assets[0].id)])
    store.document=ProjectDocument(sequence:Sequence(tracks:assets.map{Track(name:$0.url.lastPathComponent,kind:.video,clips:[Clip(assetID:$0.id,duration:duration)])},multicamGroups:[group]),assets:assets)
    store.panel = .multicam
    let host=NSHostingView(rootView:WorkspaceView(store:store).preferredColorScheme(.dark))
    host.frame=NSRect(x:0,y:0,width:1280,height:800);host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width<=1280);#expect(host.fittingSize.height<=800)
    let players=workspacePlayers(in:host)
    let output=try #require(players.first{$0.player === store.player})
    let outputRect=output.convert(output.bounds,to:host)
    let angles=players.filter{$0 !== output}
    #expect(angles.count==4)
    for angle in angles {
        let rect=angle.convert(angle.bounds,to:host)
        #expect(rect.width>0 && rect.height>0)
        #expect(rect.minX>=outputRect.maxX)
        #expect(!rect.intersects(outputRect))
    }
    #expect(outputRect.width>400)
}

@MainActor @Test func rememberedTimelineCollapseExpandsViewerWithoutHidingTransport() throws {
    _ = NSApplication.shared
    let defaults=UserDefaults.standard,key="timelineCollapsed",previous=defaults.object(forKey:"timelineCollapsed")
    defer{if let previous{defaults.set(previous,forKey:key)}else{defaults.removeObject(forKey:key)}}
    func outputHeight(collapsed:Bool)throws->Double {
        defaults.set(collapsed,forKey:key)
        let store=EditorStore()
        let host=NSHostingView(rootView:WorkspaceView(store:store).preferredColorScheme(.dark))
        host.frame=NSRect(x:0,y:0,width:1280,height:800);host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width<=1280);#expect(host.fittingSize.height<=800)
        let player=try #require(workspacePlayers(in:host).first{$0.player === store.player})
        return player.bounds.height
    }
    let expandedHeight=try outputHeight(collapsed:false),collapsedHeight=try outputHeight(collapsed:true)
    #expect(collapsedHeight>expandedHeight+150)
}

@MainActor private func workspacePlayers(in view:NSView)->[AVPlayerView] {
    (view as? AVPlayerView).map{[$0]} ?? view.subviews.flatMap{workspacePlayers(in:$0)}
}
