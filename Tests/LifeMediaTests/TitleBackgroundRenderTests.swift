import Foundation
import Testing
@preconcurrency import AVFoundation
import CoreImage
import CoreText
import LifeCore
@testable import LifeMedia

@MainActor struct TitleBackgroundRenderTests {
    private let size=CGSize(width:320,height:240)
    private func pixels(_ image:CIImage)->[UInt8]{
        var bytes=[UInt8](repeating:0,count:320*240*4)
        CIContext().render(image,toBitmap:&bytes,rowBytes:320*4,bounds:CGRect(origin:.zero,size:size),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB));return bytes
    }
    private func pixels(_ image:CGImage)->[UInt8]{pixels(CIImage(cgImage:image))}
    private func title(_ shape:TitleBackgroundShape)->TitleContent {
        .init(text:"Life\nEditor",fontSize:28,style:.init(x:0.5,y:0.43,background:.init(red:0.1,green:0.25,blue:0.4),backgroundStyle:.init(shape:shape,padding:12,cornerRadius:0.5,borderWidth:3,borderColor:.init(red:1,green:0.3,blue:0.1),shadowColor:.init(red:0.2,green:0.8,blue:0.1,alpha:0.8),shadowBlur:6,shadowOffsetX:8,shadowOffsetY:8)),animation:.init(kind:.typewriter,duration:0.5))
    }
    @Test func titleBackgroundShapesThumbnailsAndTypewriterAreStable()async throws {
        var results=Set<Data>(),glyphs:Set<Int>?

        for shape in TitleBackgroundShape.allCases {
            let content=title(shape),image=try #require(TitleRenderer.image(content,size:size))
            let bytes=pixels(image)
            var glyphOnly=content;glyphOnly.style?.background = .clear;glyphOnly.style?.backgroundStyle?.borderWidth=0;glyphOnly.style?.backgroundStyle?.shadowColor = .clear
            let glyphBytes=pixels(try #require(TitleRenderer.image(glyphOnly,size:size)))
            let glyphMask=Set(stride(from:0,to:glyphBytes.count,by:4).filter{glyphBytes[$0+3]>0})
            if let glyphs{#expect(glyphMask==glyphs)}else{glyphs=glyphMask}
            results.insert(Data(bytes));#expect(bytes==pixels(try #require(TitleRenderer.image(content,size:size))))
            let thumb=try await TitleThumbnails.shared.image(background:try #require(content.style?.backgroundStyle),color:try #require(content.style?.background))
            #expect(thumb.width==160 && thumb.height==90)
            // Transparent glyphs isolate the actual body+border+shadow. Its
            // full-string layout stays byte-identical during typewriter reveal.
            var bodyOnly=content;bodyOnly.style?.color = .clear
            let body=pixels(try #require(TitleRenderer.image(bodyOnly,size:size)))
            let partial=pixels(try #require(TitleRenderer.image(bodyOnly,size:size,visibleCharacters:1)))
            #expect(body==partial)
            let occupied=stride(from:0,to:body.count,by:4).filter{body[$0+3]>0}.count
            #expect(shape == .none || occupied>500)

        }
        #expect(results.count==5)
        var noBody=title(.none);noBody.style?.backgroundStyle?.shadowColor = .clear
        let clear=pixels(try #require(TitleRenderer.image(noBody,size:size)))
        var saved=noBody;saved.style?.background = .init(red:1,green:0,blue:0)
        #expect(clear==pixels(try #require(TitleRenderer.image(saved,size:size))))
    }
    @Test func titleBackgroundBorderAndShadowProduceIndependentPixels()throws {
        let content=title(.square),withBoth=pixels(try #require(TitleRenderer.image(content,size:size)))
        var noBorder=content;noBorder.style?.backgroundStyle?.borderWidth=0
        let withoutBorder=pixels(try #require(TitleRenderer.image(noBorder,size:size)))
        let orange=stride(from:0,to:withBoth.count,by:4).filter{withBoth[$0]>220 && withBoth[$0+1]<120 && withBoth[$0+2]<70}
        #expect(orange.count>100);#expect(orange.contains{withBoth[$0..<$0+4] != withoutBorder[$0..<$0+4]})
        var noShadow=content;noShadow.style?.backgroundStyle?.shadowColor = .clear
        let withoutShadow=pixels(try #require(TitleRenderer.image(noShadow,size:size)))
        let outside=stride(from:0,to:withBoth.count,by:4).filter{withoutShadow[$0+3]==0 && withBoth[$0+3]>8 && withBoth[$0+1]>withBoth[$0]}
        #expect(outside.count>100)
    }
    @Test func titleBackgroundLegacyNilMatchesOriginalCoreTextRaster()throws {
        let content=TitleContent(text:"Legacy\nText",fontSize:28,style:.init(x:0.5,y:0.5,background:.black,cornerRadius:0.1))
        let context=try #require(CGContext(data:nil,width:320,height:240,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        let font=CTFontCreateWithName("Helvetica-Bold" as CFString,28,nil)
        var alignment=CTTextAlignment.center
        let paragraph=withUnsafePointer(to:&alignment){pointer in var setting=CTParagraphStyleSetting(spec:.alignment,valueSize:MemoryLayout<CTTextAlignment>.size,value:pointer);return CTParagraphStyleCreate(&setting,1)}
        let attributed=NSAttributedString(string:content.text,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font,NSAttributedString.Key(kCTForegroundColorAttributeName as String):CGColor(gray:1,alpha:1),NSAttributedString.Key(kCTParagraphStyleAttributeName as String):paragraph])
        let setter=CTFramesetterCreateWithAttributedString(attributed)
        let measured=CTFramesetterSuggestFrameSizeWithConstraints(setter,CFRange(location:0,length:0),nil,CGSize(width:288,height:216),nil),padding=7.0
        let bounds=CGRect(x:160-measured.width/2-padding,y:120-measured.height/2-padding,width:ceil(measured.width)+padding*2,height:ceil(measured.height)+padding*2)
        context.setFillColor(CGColor(gray:0,alpha:1));context.addPath(CGPath(roundedRect:bounds,cornerWidth:min(bounds.width,bounds.height)*0.1,cornerHeight:min(bounds.width,bounds.height)*0.1,transform:nil));context.fillPath()
        let frame=CTFramesetterCreateFrame(setter,CFRange(location:0,length:0),CGPath(rect:bounds.insetBy(dx:padding,dy:padding),transform:nil),nil);CTFrameDraw(frame,context)
        #expect(pixels(try #require(context.makeImage()))==pixels(try #require(TitleRenderer.image(content,size:size))))
    }
    @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"]=="1"))
    func titleBackgroundSavedUndoPreviewAndDecodedExportAgree()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("life-title-background-"+UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let pipeline=MediaPipeline()
        for shape in [TitleBackgroundShape.rounded,.pill,.speechBubble] {
            let content=title(shape),clip=Clip(duration:.init(value:1,timescale:1),title:content)
            let original=ProjectDocument(sequence:.init(settings:.init(width:320,height:240),tracks:[.init(name:"Title",kind:.title,clips:[clip])]))
            var next=original;next.sequence.tracks[0].clips[0].title?.style?.backgroundStyle?.padding=18
            let editor=ProjectEditor(document:original);try editor.perform(.replace(next));editor.undo();#expect(editor.document==original);editor.redo()
            let package=root.appendingPathComponent(shape.rawValue+".lifeedit");try ProjectPackage.write(editor.document,to:package);let reopened=try ProjectPackage.read(from:package);#expect(reopened==next)
            let snapshot=ProjectSnapshot(document:reopened),prepared=try await pipeline.prepare(snapshot)
            let preview=AVAssetImageGenerator(asset:prepared.playerItem.asset);preview.videoComposition=prepared.playerItem.videoComposition;preview.requestedTimeToleranceBefore = .zero;preview.requestedTimeToleranceAfter = .zero
            let url=root.appendingPathComponent(shape.rawValue+".mov");try await pipeline.export(snapshot,to:url,options:.init(format:.proRes))
            let decoded=AVAssetImageGenerator(asset:AVURLAsset(url:url));decoded.requestedTimeToleranceBefore = .zero;decoded.requestedTimeToleranceAfter = .zero
            var frames:[Data]=[]
            for time in [CMTime(value:1,timescale:10),CMTime(value:4,timescale:10),CMTime(value:8,timescale:10)] {
                let before=pixels(try await preview.image(at:time).image),after=pixels(try await decoded.image(at:time).image)
                let difference=zip(before,after).reduce(0.0){$0+Double(abs(Int($1.0)-Int($1.1)))}/Double(before.count)
                #expect(difference<4);frames.append(Data(before))
            }
            #expect(Set(frames).count==3)
        }
    }
}
