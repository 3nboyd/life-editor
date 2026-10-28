import Testing
import AppKit
import SwiftUI
@preconcurrency import AVFoundation
import CoreImage
import LifeCore
import LifeMedia
@testable import LifeEditor

@MainActor @Test func drawingStrokeStylesGeometryAndUndoPersist()throws {
    let store=EditorStore();store.drawingMode=2;store.drawingColor = .init(red:1,green:0.2,blue:0,alpha:0.5);store.drawingWidth=0.04
    let original=store.document
    store.commitDrawing([.init(x:0.1,y:0.2),.init(x:0.8,y:0.7)])
    let added=store.document,stroke=try #require(store.selectedDrawingStroke)
    #expect(stroke.tool == .highlighter);#expect(stroke.color.alpha==0.5)
    #expect(store.selectedClip?.duration == .init(value:3,timescale:1))
    store.undo();#expect(store.document==original);store.redo();#expect(store.document==added)
    store.beginGesture();store.moveDrawingPoint(.init(x:0.2,y:0.3));store.moveDrawingPoint(.init(x:0.3,y:0.4));store.endGesture()
    let moved=store.document
    #expect(store.selectedDrawingStroke?.points[0] == .init(x:0.3,y:0.4))
    store.undo();#expect(store.document==added);store.redo();#expect(store.document==moved)
    store.editDrawingStroke{$0.tool = .pen;$0.width=0.02;$0.color.alpha=0.25}
    let styled=store.document
    #expect(try JSONDecoder().decode(ProjectDocument.self,from:JSONEncoder().encode(styled))==styled)
    store.duplicateDrawingStroke();#expect(store.selectedDrawing?.strokes.count==2)
    #expect(store.selectedDrawingStroke?.id != stroke.id)
    store.undo();#expect(store.document==styled)
    store.selectDrawingStroke(stroke.id);store.deleteDrawingStroke();#expect(store.selectedDrawing?.strokes.isEmpty==true)
    store.undo();#expect(store.document==styled)
    store.selectDrawingStroke(stroke.id);store.selectedDrawingPointIndex=1
    store.selection=nil
    #expect(store.selectedDrawingStrokeID==nil);#expect(store.selectedDrawingPointIndex==0)
}

@MainActor @Test func drawingEditingHonorsLocksAndEraserFindsSparseSegments()throws {
    let stroke=DrawingStroke(points:[.init(x:0.1,y:0.5),.init(x:0.9,y:0.5)],width:0.01)
    let clip=Clip(duration:.init(value:3,timescale:1),graphic:.drawing(.init(strokes:[stroke])))
    let store=EditorStore(),original=ProjectDocument(sequence:.init(tracks:[.init(name:"Drawing",kind:.drawing,clips:[clip])]))
    store.replace(original);store.selection=clip.id;store.selectDrawingStroke(stroke.id);store.drawingMode=3
    store.commitDrawing([.init(x:0.5,y:0.7)]);#expect(store.document==original)
    store.commitDrawing([.init(x:0.5,y:0.5)]);#expect(store.selectedDrawing?.strokes.isEmpty==true)
    store.undo();#expect(store.document==original)
    var locked=original;locked.sequence.tracks[0].isLocked=true;store.replace(locked);store.selectDrawingStroke(stroke.id)
    store.moveDrawingPoint(.init(x:0.4,y:0.4));store.duplicateDrawingStroke();store.deleteDrawingStroke();store.commitDrawing([.init(x:0.5,y:0.5)])
    #expect(store.document==locked);#expect(store.error != nil)
}

@MainActor @Test func drawingViewerCoordinatesRoundTripAndHitSegments()throws {
    let stroke=DrawingStroke(points:[.init(x:0.1,y:0.3),.init(x:0.9,y:0.3)])
    let clip=Clip(duration:.init(value:3,timescale:1),visual:.init(x:0.6,y:0.4,scaleX:0.7,scaleY:0.8,rotationDegrees:35,flipHorizontal:true),graphic:.drawing(.init(strokes:[stroke])))
    let store=EditorStore();store.replace(.init(sequence:.init(tracks:[.init(name:"Drawing",kind:.drawing,clips:[clip])])));store.selection=clip.id
    let overlay=DrawingPointOverlay(store:store,canvas:.init(width:640,height:360),origin:.init(x:20,y:15)),point=GraphicPoint(x:0.42,y:0.18)
    let roundTrip=overlay.source(overlay.display(point))
    #expect(abs(roundTrip.x-point.x)<1e-12);#expect(abs(roundTrip.y-point.y)<1e-12)
    overlay.select(at:overlay.display(.init(x:0.5,y:0.3)));#expect(store.selectedDrawingStrokeID==stroke.id)
    overlay.select(at:.init(x:0,y:0));#expect(store.selectedDrawingStrokeID==nil)
}

@MainActor @Test func drawingInspectorFitsNarrowPanel()throws {
    _ = NSApplication.shared
    let store=EditorStore();store.drawingMode=1;store.commitDrawing([.init(x:0.1,y:0.2),.init(x:0.8,y:0.7)]);store.drawingMode=4
    let host=NSHostingView(rootView:DrawingControls(store:store).padding(12))
    host.frame = .init(x:0,y:0,width:248,height:600);host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width<=248);#expect(host.fittingSize.height<=600)
}

@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"]=="1"))
func editedDrawingAlphaMatchesPreviewExportAndReopen()async throws {
    _ = NSApplication.shared
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("life-drawing-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
    let store=EditorStore();store.replace(.init(sequence:.init(settings:.init(width:320,height:180))))
    store.drawingMode=2;store.drawingWidth=0.1;store.drawingColor = .init(red:1,green:0,blue:0,alpha:0.5)
    store.commitDrawing([.init(x:0.2,y:0.5),.init(x:0.8,y:0.5)])
    store.selectedDrawingPointIndex=1;store.moveDrawingPoint(.init(x:0.7,y:0.5))
    let graphic=try #require(store.selectedClip?.graphic),image=try #require(GraphicRenderer.image(graphic,size:.init(width:320,height:180)))
    var pixel=[UInt8](repeating:0,count:4)
    CIContext().render(image,toBitmap:&pixel,rowBytes:4,bounds:.init(x:160,y:90,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
    #expect(abs(Int(pixel[3])-45)<=1) // .5 color alpha × .35 highlighter opacity.
    let package=root.appendingPathComponent("Drawing.lifeedit");try ProjectPackage.write(store.document,to:package)
    let reopened=try ProjectPackage.read(from:package);#expect(reopened==store.document)
    let media=MediaPipeline(),prepared=try await media.prepare(.init(document:reopened))
    let preview=AVAssetImageGenerator(asset:prepared.playerItem.asset);preview.videoComposition=prepared.playerItem.videoComposition
    let destination=root.appendingPathComponent("drawing.mov");try await media.export(.init(document:reopened),to:destination,options:.init(format:.proRes))
    let output=AVAssetImageGenerator(asset:AVURLAsset(url:destination)),time=CMTime(value:1,timescale:1)
    func pixels(_ image:CGImage)->[UInt8]{
        var bytes=[UInt8](repeating:0,count:320*180*4)
        bytes.withUnsafeMutableBytes{memory in let context=CGContext(data:memory.baseAddress,width:320,height:180,bitsPerComponent:8,bytesPerRow:320*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;context.draw(image,in:.init(x:0,y:0,width:320,height:180))};return bytes
    }
    let live=pixels(try await preview.image(at:time).image),offline=pixels(try await output.image(at:time).image)
    #expect(zip(live,offline).reduce(0.0){$0+Double(abs(Int($1.0)-Int($1.1)))}/Double(live.count)<5)
    #expect(offline[(90*320+160)*4]>30)
}

@MainActor @Test func drawingEraserUsesCanvasPixelsAndSweptGestureSegments()throws {
    for (width,height,portrait) in [(1920,1080,false),(1080,1920,true)] {
        let points:[GraphicPoint]=portrait ? [.init(x:0.3,y:0.5),.init(x:0.7,y:0.5)]:[.init(x:0.5,y:0.3),.init(x:0.5,y:0.7)]
        let stroke=DrawingStroke(points:points,width:0.01)
        let clip=Clip(duration:.init(value:3,timescale:1),visual:.init(scaleX:0.5,scaleY:0.75,rotationDegrees:25),graphic:.drawing(.init(strokes:[stroke])))
        let original=ProjectDocument(sequence:.init(settings:.init(width:width,height:height),tracks:[.init(name:"Drawing",kind:.drawing,clips:[clip])]))
        let store=EditorStore();store.replace(original);store.selection=clip.id;store.drawingMode=3;store.drawingWidth=0.006
        // Both are 19.2 px from the stroke center; the combined radius is 11.88 px.
        store.commitDrawing([portrait ? .init(x:0.5,y:0.51):.init(x:0.51,y:0.5)])
        #expect(store.document==original)
        // 9.6 px is inside the brush plus half the stroke width.
        store.commitDrawing([portrait ? .init(x:0.5,y:0.505):.init(x:0.505,y:0.5)])
        #expect(store.selectedDrawing?.strokes.isEmpty==true)
        store.undo();#expect(store.document==original)
        // The gesture crosses the stroke even though neither event endpoint touches it.
        let gesture:[GraphicPoint]=portrait ? [.init(x:0.5,y:0.1),.init(x:0.5,y:0.9)]:[.init(x:0.1,y:0.5),.init(x:0.9,y:0.5)]
        store.commitDrawing(gesture);#expect(store.selectedDrawing?.strokes.isEmpty==true)
        store.undo();#expect(store.document==original)
        // A parallel swept gesture well outside the footprint leaves geometry intact.
        store.commitDrawing(portrait ? [.init(x:0.1,y:0.6),.init(x:0.9,y:0.6)]:[.init(x:0.6,y:0.1),.init(x:0.6,y:0.9)])
        #expect(store.document==original)
    }
}

@Test func pendingDrawingOutlineScalesItsFootprintAndEraserRadius()throws {
    let canvas=CGSize(width:200,height:100),point=GraphicPoint(x:0.5,y:0.5)
    let outline=DrawingPreviewGeometry.outline([point],width:0.1,canvas:canvas)
    var transform=DrawingPreviewGeometry.transform(.init(scaleX:0.5,scaleY:0.25),canvas:canvas,origin:.zero)
    let bounds=try #require(outline.cgPath.copy(using:&transform)).boundingBoxOfPath
    #expect(abs(bounds.width-5)<1e-10);#expect(abs(bounds.height-2.5)<1e-10)
    #expect(abs(bounds.midX-100)<1e-10);#expect(abs(bounds.midY-50)<1e-10)
    let eraserRadius=0.006
    let brush=DrawingPreviewGeometry.outline([point],width:2*eraserRadius,canvas:canvas).boundingRect
    #expect(abs(brush.width-2*eraserRadius*100)<1e-10)
    // A line's round caps are transformed together with its centerline.
    let line=DrawingPreviewGeometry.outline([.init(x:0.25,y:0.5),.init(x:0.75,y:0.5)],width:0.1,canvas:canvas)
    let lineBounds=try #require(line.cgPath.copy(using:&transform)).boundingBoxOfPath
    #expect(abs(lineBounds.width-55)<1e-10);#expect(abs(lineBounds.height-2.5)<1e-10)
}
