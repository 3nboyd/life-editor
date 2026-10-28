import Testing
import AppKit
@preconcurrency import AVFoundation
import LifeCore
import LifeMedia
@testable import LifeEditor

@MainActor @Test func emojiStickersRemainEditableTimedTitlesAndUndo()throws {
    let store=EditorStore(),initial=ProjectDocument(sequence:.init(settings:.init(width:320,height:180)))
    store.replace(initial);store.playheadTime = .init(value:1,timescale:1)
    store.addEmojiSticker("🎸")
    let inserted=store.document
    #expect(store.selectedClip?.title?.style?.fontName=="AppleColorEmoji")
    #expect(store.selectedClip?.title?.style?.background == .clear)
    #expect(store.selectedClip?.start == .init(value:1,timescale:1))
    #expect(store.selectedClip?.duration == .init(value:3,timescale:1))
    store.undo();#expect(store.document==initial);store.redo();#expect(store.document==inserted)
    store.editSelected{$0.title?.text="👩🏽‍🎓✨"}
    let edited=store.document
    #expect(try JSONDecoder().decode(ProjectDocument.self,from:JSONEncoder().encode(edited))==edited)
    store.undo();#expect(store.document==inserted)
    store.addEmojiSticker("  ");#expect(store.document==inserted)
}

@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"]=="1"))
func emojiStickerColorGlyphsMatchPreviewAndExport()async throws {
    _ = NSApplication.shared
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("life-emoji-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:root)}
    let store=EditorStore();store.replace(ProjectDocument(sequence:.init(settings:.init(width:320,height:180))))
    store.addEmojiSticker("😀🎸")
    let package=root.appendingPathComponent("Emoji.lifeedit")
    try ProjectPackage.write(store.document,to:package)
    let reopened=try ProjectPackage.read(from:package)
    #expect(reopened==store.document)
    let media=MediaPipeline(),prepared=try await media.prepare(.init(document:reopened))
    let preview=AVAssetImageGenerator(asset:prepared.playerItem.asset);preview.videoComposition=prepared.playerItem.videoComposition
    let destination=root.appendingPathComponent("emoji.mov")
    try await media.export(.init(document:reopened),to:destination,options:.init(format:.proRes))
    let output=AVAssetImageGenerator(asset:AVURLAsset(url:destination)),time=CMTime(value:1,timescale:1)
    func pixels(_ image:CGImage)->[UInt8]{
        var bytes=[UInt8](repeating:0,count:320*180*4)
        bytes.withUnsafeMutableBytes{memory in
            let context=CGContext(data:memory.baseAddress,width:320,height:180,bitsPerComponent:8,bytesPerRow:320*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:320,height:180))
        };return bytes
    }
    let live=pixels(try await preview.image(at:time).image),offline=pixels(try await output.image(at:time).image)
    #expect(zip(live,offline).reduce(0.0){$0+Double(abs(Int($1.0)-Int($1.1)))}/Double(live.count)<5)
    let colored=stride(from:0,to:offline.count,by:4).filter{max(offline[$0],offline[$0+1],offline[$0+2])-min(offline[$0],offline[$0+1],offline[$0+2])>40}.count
    #expect(colored>100)
    #expect(offline[0]<10 && offline[1]<10 && offline[2]<10)
}
