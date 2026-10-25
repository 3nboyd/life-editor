import Testing
import AppKit
import SwiftUI
import AVKit
import LifeCore
import LifeMedia
@testable import LifeEditor

/// Opt-in native view captures. AVPlayer's hardware layer is replaced only in
/// this harness with a frame from the same render plan; no product UI is mocked.
@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_CAPTURE_DOCUMENTATION"]=="1"))
func captureDocumentationWorkspace()async throws {
    _ = NSApplication.shared
    let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let output=root.appendingPathComponent("docs/screenshots"),poster=output.appendingPathComponent("fixtures/rehearsal.png")
    let scratch=FileManager.default.temporaryDirectory.appendingPathComponent("life-documentation-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:scratch,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:scratch)}
    let wav=scratch.appendingPathComponent("Session.wav"),format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
    do {
    let file=try AVAudioFile(forWriting:wav,settings:format.settings),buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:48000)!
    buffer.frameLength=48000
    for second in 0..<16 {
        for i in 0..<48000 {let t=Double(second)+Double(i)/48000,beat=exp(-12*t.truncatingRemainder(dividingBy:0.5)),value=Float((0.15+0.3*beat)*sin(2 * .pi*220*t));buffer.floatChannelData![0][i]=value;buffer.floatChannelData![1][i]=value*0.8}
        try file.write(from:buffer)
    }
    }
    let image=MediaAsset(url:poster,kind:.image,duration:.init(value:16,timescale:1)),audio=MediaAsset(url:wav,kind:.audio,duration:.init(value:16,timescale:1))
    let music=Clip(name:"Session · master",assetID:audio.id,duration:audio.duration,volume:.init(points:[.init(time:.zero,value:0),.init(time:.init(value:2,timescale:1),value:0.8),.init(time:.init(value:13,timescale:1),value:0.8),.init(time:.init(value:16,timescale:1),value:0)]))
    let picture=Clip(name:"Rehearsal",assetID:image.id,duration:image.duration)
    let title=Clip(name:"Opening title",start:.init(value:2,timescale:1),duration:.init(value:7,timescale:1),title:.init(text:"AFTER HOURS",fontSize:82))
    let document=ProjectDocument(name:"After Hours",sequence:Sequence(tracks:[Track(name:"Master",kind:.audio,clips:[music]),Track(name:"Picture",kind:.image,clips:[picture]),Track(name:"Titles",kind:.title,clips:[title])],markers:[.init(time:.init(value:4,timescale:1),name:"Verse"),.init(time:.init(value:10,timescale:1),name:"Chorus")],musicalGrid:.init(bpm:120)),assets:[image,audio])
    let store=EditorStore();store.replace(document);store.pixelsPerSecond=66;store.seek(6)
    defer{store.setPlaybackMeterVisible(false);store.replace(ProjectDocument());UserDefaults.standard.removeObject(forKey:"LifeEditor.timeline.heights.v1."+document.id.uuidString)}
    let prepared=try await MediaPipeline().prepare(ProjectSnapshot(document:document)),generator=AVAssetImageGenerator(asset:prepared.playerItem.asset)
    generator.videoComposition=prepared.playerItem.videoComposition
    let frame=try await generator.image(at:CMTime(value:6,timescale:1)).image
    for (name,panel,selection) in [("workspace",nil as EditorStore.InspectorPanel?,nil as UUID?),("effects",EditorStore.InspectorPanel.effects,picture.id),("audio",EditorStore.InspectorPanel.audio,music.id)] {
        store.panel=panel;store.selection=selection
        let host=NSHostingView(rootView:WorkspaceView(store:store).preferredColorScheme(.dark));host.frame=NSRect(x:0,y:0,width:1440,height:900);host.layoutSubtreeIfNeeded()
        func compactTracks(_ view:NSView){
            if let timeline=view as? TimelineCanvas {for track in document.sequence.tracks{_ = timeline.setTrackHeight(track.kind == .audio ? 80:56,for:track.id)};timeline.loadWaveforms()}
            for child in view.subviews{compactTracks(child)}
        }
        compactTracks(host)
        try await Task.sleep(for:.seconds(2));host.layoutSubtreeIfNeeded()
        func posterize(_ view:NSView){
            if let player=view as? AVPlayerView {let still=NSImageView(frame:player.bounds);still.image=NSImage(cgImage:frame,size:.zero);still.imageScaling = .scaleProportionallyUpOrDown;still.autoresizingMask=[.width,.height];player.addSubview(still)}
            else{for child in view.subviews{posterize(child)}}
        }
        posterize(host);host.layoutSubtreeIfNeeded()
        let bitmap=try #require(host.bitmapImageRepForCachingDisplay(in:host.bounds));host.cacheDisplay(in:host.bounds,to:bitmap)
        try #require(bitmap.representation(using:.png,properties:[:])).write(to:output.appendingPathComponent(name+".png"))
        #expect(host.fittingSize.width<=1440 && host.fittingSize.height<=900)
    }
}
