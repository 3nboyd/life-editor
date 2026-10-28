import Testing
import AppKit
import CoreText
import CoreImage
@preconcurrency import AVFoundation
import LifeCore
@testable import LifeMedia
@testable import LifeEditor

@MainActor @Test func installedTitleFontsMatchWeightAndItalicWithoutReplacingMissingNames()throws {
    let italic=NSFontTraitMask.italicFontMask.rawValue
    let catalog=InstalledTitleFonts(faces:[
        .init(name:"A-BoldItalic",family:"A",label:"Bold Italic",weight:9,traits:italic),
        .init(name:"B-Regular",family:"B",label:"Regular",weight:5,traits:0),
        .init(name:"B-Italic",family:"B",label:"Italic",weight:5,traits:italic),
        .init(name:"B-BoldItalic",family:"B",label:"Bold Italic",weight:9,traits:italic)])
    #expect(catalog.matchingFace(in:"B",from:"A-BoldItalic")?.name=="B-BoldItalic")
    #expect(catalog.matchingFace(in:"B",from:"Missing")?.name=="B-Regular")
    #expect(catalog.matchingFace(in:"Unknown",from:"A-BoldItalic")==nil)
    let style=TitleStyle(fontName:"NotInstalled-LifeEditor",background:.black,typography:.init(alignment:.left,letterSpacing:3,lineSpacing:8))
    let clip=Clip(duration:.init(value:2,timescale:1),title:.init(text:"Keep layout",fontSize:48,style:style)),store=EditorStore()
    let original=ProjectDocument(sequence:.init(tracks:[.init(name:"Title",kind:.title,clips:[clip])]))
    store.replace(original);store.selection=clip.id
    let controls=TitleFontControls(store:store,catalog:catalog)
    #expect(controls.currentName=="NotInstalled-LifeEditor");#expect(store.document==original)
    controls.selectFace("Unknown");#expect(store.document==original)
    controls.selectFamily("B")
    let edited=store.document
    var expected=style;expected.fontName="B-Regular"
    #expect(store.selectedClip?.title?.style==expected)
    #expect(store.selectedClip?.title?.fontSize==48)
    let data=try JSONEncoder().encode(edited)
    #expect(try JSONDecoder().decode(ProjectDocument.self,from:data)==edited)
    store.undo();#expect(store.document==original)
    store.redo();#expect(store.document==edited)
}

@MainActor @Test func installedTitleFontCatalogUsesNativePostScriptFacesAndSharedRenderer()throws {
    _ = NSApplication.shared
    let catalog=InstalledTitleFonts.shared
    #expect(catalog.families.count>6)
    // A registered/aliased face remains available even outside enumerated families.
    let uncatalogued=InstalledTitleFonts(faces:[])
    #expect(uncatalogued.face(named:"Helvetica-Bold")?.name=="Helvetica-Bold")
    #expect(uncatalogued.face(named:"NotInstalled-LifeEditor")==nil)
    let first=try #require(catalog.face(named:"Helvetica-Bold")),second=try #require(catalog.face(named:"Georgia"))
    #expect(NSFont(name:first.name,size:24)?.familyName==first.family)
    let ctFont=CTFontCreateWithName(second.name as CFString,24,nil)
    #expect(CTFontCopyPostScriptName(ctFont) as String==second.name)
    let store=EditorStore(),clip=Clip(duration:.init(value:2,timescale:1),title:.init(text:"Music Aa 123",fontSize:40))
    store.replace(.init(sequence:.init(tracks:[.init(name:"Text",kind:.title,clips:[clip])])));store.selection=clip.id
    let controls=TitleFontControls(store:store)
    controls.selectFace(second.name)
    let title=try #require(store.selectedClip?.title)
    #expect(title.style?.fontName==second.name)
    let image=try #require(TitleRenderer.image(title,size:.init(width:640,height:360)))
    var other=title;other.style?.fontName=first.name
    let otherImage=try #require(TitleRenderer.image(other,size:.init(width:640,height:360)))
    let context=CIContext(),bounds=CGRect(x:0,y:0,width:640,height:360)
    let rendered=try #require(context.createCGImage(image,from:bounds)),alternative=try #require(context.createCGImage(otherImage,from:bounds))
    #expect(rendered.dataProvider?.data != alternative.dataProvider?.data)
    let restored=try JSONDecoder().decode(ProjectDocument.self,from:JSONEncoder().encode(store.document))
    let restoredTitle=try #require(restored.sequence.tracks[0].clips[0].title)
    let restoredImage=try #require(TitleRenderer.image(restoredTitle,size:.init(width:640,height:360)))
    let reopened=try #require(context.createCGImage(restoredImage,from:bounds))
    #expect(rendered.dataProvider?.data==reopened.dataProvider?.data)
}


@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"]=="1"))
func selectedInstalledFontFacesSurvivePackageAndMatchDecodedExport()async throws {
    _ = NSApplication.shared
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("life-title-fonts-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:root)}
    let names=["Georgia","Georgia-Bold"],store=EditorStore()
    let clips=names.enumerated().map{index,_ in
        Clip(start:.init(value:Int64(index),timescale:1),duration:.init(value:1,timescale:1),title:.init(text:"Music Aa 123",fontSize:28))
    }
    let original=ProjectDocument(sequence:.init(settings:.init(width:320,height:180),tracks:[.init(name:"Title",kind:.title,clips:clips)]))
    store.replace(original)
    for (clip,name) in zip(clips,names){
        store.selection=clip.id
        let controls=TitleFontControls(store:store)
        controls.selectFace(name)
        #expect(store.selectedClip?.title?.style?.fontName==name)
    }
    let edited=store.document
    store.undo();#expect(store.document != edited)
    store.redo();#expect(store.document==edited)
    let package=root.appendingPathComponent("Fonts.lifeedit")
    try ProjectPackage.write(edited,to:package)
    let reopened=try ProjectPackage.read(from:package)
    #expect(reopened==edited)
    let pipeline=MediaPipeline(),snapshot=ProjectSnapshot(document:reopened)
    let prepared=try await pipeline.prepare(snapshot)
    let preview=AVAssetImageGenerator(asset:prepared.playerItem.asset)
    preview.videoComposition=prepared.playerItem.videoComposition
    preview.requestedTimeToleranceBefore = .zero;preview.requestedTimeToleranceAfter = .zero
    let output=root.appendingPathComponent("Fonts.mov")
    try await pipeline.export(snapshot,to:output,options:.init(format:.proRes))
    let decoded=AVAssetImageGenerator(asset:AVURLAsset(url:output))
    decoded.requestedTimeToleranceBefore = .zero;decoded.requestedTimeToleranceAfter = .zero
    let context=CIContext(),bounds=CGRect(x:0,y:0,width:320,height:180)
    func pixels(_ image:CGImage)->[UInt8]{
        var bytes=[UInt8](repeating:0,count:320*180*4)
        context.render(CIImage(cgImage:image),toBitmap:&bytes,rowBytes:320*4,bounds:bounds,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
        return bytes
    }
    var previewFrames:[Data]=[]
    for time in [CMTime(value:1,timescale:2),CMTime(value:3,timescale:2)]{
        let before=pixels(try await preview.image(at:time).image),after=pixels(try await decoded.image(at:time).image)
        let difference=zip(before,after).reduce(0.0){$0+Double(abs(Int($1.0)-Int($1.1)))}/Double(before.count)
        #expect(difference<4)
        previewFrames.append(Data(before))
    }
    #expect(Set(previewFrames).count==2)
}
