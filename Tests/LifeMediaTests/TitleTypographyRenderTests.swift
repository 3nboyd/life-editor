import Foundation
import Testing
@preconcurrency import AVFoundation
import CoreImage
import LifeCore
@testable import LifeMedia

@MainActor struct TitleTypographyRenderTests {
    private let size=CGSize(width:320,height:240)
    private func pixels(_ image:CIImage)->[UInt8]{
        var bytes=[UInt8](repeating:0,count:320*240*4)
        CIContext().render(image,toBitmap:&bytes,rowBytes:1280,bounds:CGRect(origin:.zero,size:size),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB));return bytes
    }
    private func bands(_ bytes:[UInt8])->[(Int,Int,Int)]{
        var result:[(Int,Int,Int)]=[],start:Int?,xs:[Int]=[]
        for y in 0...240 {
            let row=y<240 ? (0..<320).filter{bytes[(y*320+$0)*4+3]>100}:[]
            if !row.isEmpty{if start==nil{start=y};xs += row}
            else if let first=start {result.append((first,y,xs.min()!));start=nil;xs=[]}
        }
        return result
    }
    @Test func titleTypographyAlignmentAndSpacingChangeActualGlyphLayout()throws {
        let base=TitleContent(text:"MMMMMM\nMM",fontSize:28,style:.init(x:0.5,y:0.5))
        var outputs=[TitleAlignment:[(Int,Int,Int)]]()
        for alignment in TitleAlignment.allCases {
            var title=base;title.style?.typography = .init(alignment:alignment)
            let bytes=pixels(try #require(TitleRenderer.image(title,size:size)))
            let lines=bands(bytes);#expect(lines.count==2);outputs[alignment]=lines
            // Typewriter uses the complete layout. Revealing a whole first line
            // leaves that line exactly where the full title places it.
            let partial=pixels(try #require(TitleRenderer.image(title,size:size,visibleCharacters:6)))
            for i in stride(from:0,to:partial.count,by:4) where partial[i+3]>0 {#expect(Array(partial[i..<i+4])==Array(bytes[i..<i+4]))}
        }
        let left=try #require(outputs[.left]),center=try #require(outputs[.center]),right=try #require(outputs[.right])
        // Bitmap rows are top-down in this CI render; the first band is the
        // long first line. Short second lines follow the chosen paragraph edge.
        #expect(abs(left[0].2-left[1].2)<=2)
        #expect(center[1].2>center[0].2+20)
        #expect(right[1].2>center[1].2+20)
        var spaced=base;spaced.style?.typography = .init(letterSpacing:5,lineSpacing:18)
        let normal=pixels(try #require(TitleRenderer.image(base,size:size))),changed=pixels(try #require(TitleRenderer.image(spaced,size:size)))
        #expect(normal != changed)
        let before=bands(normal),after=bands(changed);#expect(after.count==2)
        #expect(after[1].0-after[0].0>=before[1].0-before[0].0+17)
        let originalWidth=(0..<320).filter{normal[before[0].0*1280+$0*4+3]>100}
        let spacedWidth=(0..<320).filter{changed[after[0].0*1280+$0*4+3]>100}
        #expect((spacedWidth.last! - spacedWidth.first!) > (originalWidth.last! - originalWidth.first!)+15)
    }
    @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"]=="1"))
    func titleTypographyPreviewAndDecodedExportAgree()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let title=TitleContent(text:"Aligned\nTwo lines",fontSize:28,style:.init(x:0.5,y:0.5,typography:.init(alignment:.right,letterSpacing:3,lineSpacing:12)),animation:.init(kind:.typewriter,duration:0.5))
        let document=ProjectDocument(sequence:.init(settings:.init(width:320,height:240),tracks:[.init(name:"Text",kind:.title,clips:[.init(duration:.init(value:1,timescale:1),title:title)])]))
        let package=root.appendingPathComponent("Layout.lifeedit");try ProjectPackage.write(document,to:package)
        let snapshot=ProjectSnapshot(document:try ProjectPackage.read(from:package)),pipeline=MediaPipeline(),prepared=try await pipeline.prepare(snapshot)
        let preview=AVAssetImageGenerator(asset:prepared.playerItem.asset);preview.videoComposition=prepared.playerItem.videoComposition;preview.requestedTimeToleranceBefore = .zero;preview.requestedTimeToleranceAfter = .zero
        let destination=root.appendingPathComponent("layout.mov");try await pipeline.export(snapshot,to:destination,options:.init(format:.proRes))
        let exported=AVAssetImageGenerator(asset:AVURLAsset(url:destination));exported.requestedTimeToleranceBefore = .zero;exported.requestedTimeToleranceAfter = .zero
        for time in [CMTime(value:2,timescale:10),CMTime(value:8,timescale:10)] {
            let before=pixels(CIImage(cgImage:try await preview.image(at:time).image)),after=pixels(CIImage(cgImage:try await exported.image(at:time).image))
            let error=zip(before,after).reduce(0.0){$0+Double(abs(Int($1.0)-Int($1.1)))}/Double(before.count);#expect(error<4)
        }
    }
}
