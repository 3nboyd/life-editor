import Testing
import Foundation
import AppKit
import ImageIO
import LifeCore
@testable import LifeEditor
private func filmTime(_ n:Int64)->RationalTime{.init(value:n,timescale:1)}
@Test func filmstripVisibleMappingIsBoundedAndSourceAccurate(){
    let clip=Clip(start:filmTime(10),duration:filmTime(3600),sourceStart:filmTime(5),speed:2)
    let cells=FilmstripPlanner.cells(clip:clip,assetKind:.video,visibleRange:10...12,pixelsPerSecond:100,tileWidth:100)
    #expect(cells.count==2);#expect(cells[0].sourceTime==filmTime(6));#expect(cells[1].sourceTime==filmTime(8))
    #expect(FilmstripPlanner.cells(clip:clip,assetKind:.video,visibleRange:10...3610,pixelsPerSecond:10000).count==24)
    #expect(FilmstripPlanner.cells(clip:clip,assetKind:.image,visibleRange:50...51,pixelsPerSecond:100).allSatisfy{$0.sourceTime == .zero})
    #expect(FilmstripPlanner.cells(clip:clip,assetKind:.audio,visibleRange:10...12,pixelsPerSecond:100).isEmpty)
}
@MainActor @Test func trackLayoutPersistsBoundsHitTestingAndCanvasGeometry() throws {
    let name="TimelineLayoutTests."+UUID().uuidString,defaults=try #require(UserDefaults(suiteName:name));defer{defaults.removePersistentDomain(forName:name)}
    let project=UUID(),a=Track(name:"A",kind:.video),clip=Clip(duration:filmTime(2),title:TitleContent(text:"Test")),b=Track(name:"B",kind:.title,clips:[clip])
    let layout=TimelineLayout(projectID:project,defaults:defaults)
    #expect(layout.setHeight(500,for:a.id));#expect(layout.height(for:a.id)==240)
    #expect(!layout.setHeight(.nan,for:a.id));#expect(layout.setHeight(1,for:b.id))
    #expect(layout.rows(for:[a,b])[1].top==272);#expect(layout.row(at:272,tracks:[a,b])==1)
    #expect(TimelineLayout(projectID:project,defaults:defaults).height(for:a.id)==240)
    layout.useProject(UUID());#expect(layout.height(for:a.id)==76);layout.useProject(project)
    let store=EditorStore();store.replace(ProjectDocument(id:project,sequence:Sequence(tracks:[a,b])))
    let canvas=TimelineCanvas(store:store,layout:layout),before=store.document
    #expect(canvas.rect(clip,row:0).height==42)
    #expect(canvas.resizeTrack(b.id,by:16));#expect(canvas.rect(clip,row:0).height==58)
    #expect(store.document==before)
    canvas.refreshAccessibility();let count=canvas.accessibilityRebuildCount;canvas.refreshAccessibility();#expect(canvas.accessibilityRebuildCount==count)
    #expect(canvas.resizeTrack(b.id,by:16));#expect(canvas.accessibilityRebuildCount>count)
}
private func filmPixel(_ image:CGImage)->[UInt8]{
    var bytes=[UInt8](repeating:0,count:4)
    bytes.withUnsafeMutableBytes{buffer in
        let context=CGContext(data:buffer.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image,in:CGRect(x:0,y:0,width:1,height:1))
    };return bytes
}
private func writeFilmstripPNG(_ url:URL,red:CGFloat,blue:CGFloat)throws{
    let context=try #require(CGContext(data:nil,width:640,height:360,bitsPerComponent:8,bytesPerRow:2560,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(red:red,green:0,blue:blue,alpha:1);context.fill(CGRect(x:0,y:0,width:640,height:360))
    let image=try #require(context.makeImage()),destination=try #require(CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil));CGImageDestinationAddImage(destination,image,nil);#expect(CGImageDestinationFinalize(destination))
}
@Test func filmstripNativeCacheInvalidatesSourceEffectsAndHonorsBudget() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:directory)}
    let url=directory.appendingPathComponent("image.png");try writeFilmstripPNG(url,red:1,blue:0)
    let asset=MediaAsset(url:url,kind:.image,duration:filmTime(5)),cache=TimelineThumbnailCache(budgetBytes:256000)
    let first=try await cache.image(for:asset,sourceTime:.zero)
    #expect(first.image.width<=320 && first.image.height<=180);#expect(filmPixel(first.image)[0]>240)
    try writeFilmstripPNG(url,red:0,blue:1);try FileManager.default.setAttributes([.modificationDate:Date().addingTimeInterval(2)],ofItemAtPath:url.path)
    let second=try await cache.image(for:asset,sourceTime:.zero)
    #expect(filmPixel(second.image)[2]>240);#expect(first.key != second.key);#expect(await cache.memoryBytes<=256000);#expect(await cache.activeJobs==0)
    let gray=try await cache.image(for:asset,sourceTime:.zero,effects:[EffectInstance(stableID:"life.filter.grayscale")])
    let pixel=filmPixel(gray.image);#expect(abs(Int(pixel[0])-Int(pixel[2]))<4);#expect(gray.key != second.key)
    let old=try TimelineThumbnailCache.logicalKey(sourceStamp:"same",sourceTime:.zero,effects:[])
    let changed=try TimelineThumbnailCache.logicalKey(sourceStamp:"same",sourceTime:filmTime(1),effects:[]);#expect(old != changed)
    let task=Task{try Task.checkCancellation();return try await cache.image(for:asset,sourceTime:filmTime(2))};task.cancel()
    do{_ = try await task.value;Issue.record("Cancelled thumbnail decoded")}catch is CancellationError{}catch{Issue.record("Unexpected cancellation error: \(error)")}
    #expect(await cache.activeJobs==0)
}

@MainActor @Test func trackDividerDragAndKeyboardResizeWithoutEditingDocument() throws {
    _ = NSApplication.shared
    let name="TimelineDragTests."+UUID().uuidString,defaults=try #require(UserDefaults(suiteName:name));defer{defaults.removePersistentDomain(forName:name)}
    let track=Track(name:"Video",kind:.video),store=EditorStore();store.replace(ProjectDocument(sequence:Sequence(tracks:[track])))
    let layout=TimelineLayout(projectID:store.document.id,defaults:defaults),canvas=TimelineCanvas(store:store,layout:layout)
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:400),styleMask:[.titled],backing:.buffered,defer:false);window.contentView=canvas;canvas.frame=NSRect(x:0,y:0,width:800,height:400)
    let before=store.document
    func mouse(_ type:NSEvent.EventType,_ y:Double)->NSEvent {NSEvent.mouseEvent(with:type,location:canvas.convert(NSPoint(x:135,y:y),to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!}
    canvas.mouseDown(with:mouse(.leftMouseDown,108));canvas.mouseDragged(with:mouse(.leftMouseDragged,148));canvas.mouseUp(with:mouse(.leftMouseUp,148))
    #expect(layout.height(for:track.id)==116)
    let key=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.option,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:125));canvas.keyDown(with:key)
    #expect(layout.height(for:track.id)==132);#expect(store.document==before)
    let children=try #require(canvas.accessibilityChildren() as? [NSAccessibilityElement]);let slider=try #require(children.first{$0.accessibilityLabel()=="Height Video"})
    #expect(slider.accessibilityPerformDecrement());#expect(layout.height(for:track.id)==116)
    window.contentView=nil
}
@MainActor @Test func timelinePlacementProposalShowsCandidateAndRejectsPointerAndKeyEdits() throws {
    _ = NSApplication.shared
    let clip=Clip(duration:filmTime(2),title:TitleContent(text:"Original")),track=Track(name:"Title",kind:.title,clips:[clip]),store=EditorStore()
    store.replace(ProjectDocument(sequence:Sequence(tracks:[track])));store.selection=clip.id
    let original=store.document,proposal=try SpliceEditing.proposal(for:.insertCopies(clipIDs:[clip.id],at:filmTime(1)),in:original)
    store.placementProposal=proposal
    let canvas=TimelineCanvas(store:store),window=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:400),styleMask:[.titled],backing:.buffered,defer:false)
    window.contentView=canvas;canvas.frame=NSRect(x:0,y:0,width:800,height:400)
    #expect(canvas.tracks.flatMap(\.clips).count>original.sequence.tracks.flatMap(\.clips).count)
    let inserted=try #require(canvas.tracks.flatMap(\.clips).first{proposal.insertedClipIDs.contains($0.id)})
    #expect(abs(Double(canvas.rect(inserted,row:0).minX)-(140+inserted.start.seconds*store.pixelsPerSecond))<0.000001)
    let box=canvas.rect(inserted,row:0)
    func mouse(_ type:NSEvent.EventType,_ x:Double)->NSEvent{NSEvent.mouseEvent(with:type,location:canvas.convert(NSPoint(x:x,y:box.midY),to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!}
    canvas.mouseDown(with:mouse(.leftMouseDown,box.midX));canvas.mouseDragged(with:mouse(.leftMouseDragged,box.midX+80));canvas.mouseUp(with:mouse(.leftMouseUp,box.midX+80))
    let delete=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:51));canvas.keyDown(with:delete)
    #expect(store.document==original);#expect(store.placementProposal?.document==proposal.document)
    canvas.refreshAccessibility();let children=try #require(canvas.accessibilityChildren() as? [NSAccessibilityElement]);let clipButton=try #require(children.first{$0.accessibilityLabel()?.contains(inserted.name)==true})
    #expect(!clipButton.accessibilityPerformPress());#expect(store.document==original)
    store.placementProposal=nil;#expect(canvas.tracks.flatMap(\.clips)==[clip]);window.contentView=nil
}
