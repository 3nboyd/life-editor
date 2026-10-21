import Testing
import Foundation
@preconcurrency import AVFoundation
import CoreImage
import LifeCore
@testable import LifeMedia

@MainActor struct TitleAnimationRenderTests {
    @Test func typewriterKeepsGraphemesAndFullLayoutPositions() throws {
        let title = TitleContent(text: "AB👩‍🎤CD", fontSize: 24, style: .init(x: 0.5, y: 0.5))
        let size = CGSize(width: 256, height: 96)
        let context = CIContext()
        func pixels(_ count: Int?) throws -> [UInt8] {
            let image = try #require(TitleRenderer.image(title, size: size, visibleCharacters: count))
            return bytes(try #require(context.createCGImage(image, from: CGRect(origin: .zero, size: size))))
        }
        let full = try pixels(nil)
        #expect(try pixels(0).allSatisfy { $0 == 0 })
        for count in 1..<title.text.count {
            let partial = try pixels(count)
            #expect(partial == (try pixels(count)))
            #expect(partial != full)
            // Revealing runs from the complete layout preserves every existing
            // pixel's location, including an emoji consisting of several scalars.
            #expect(zip(partial, full).allSatisfy { Int($0) <= Int($1) + 1 })
        }
        #expect(try pixels(title.text.count) == full)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"] == "1"))
    func everyTitleEntranceSavesReopensSeeksAndMatchesExport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("life-title-animations-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pipeline = MediaPipeline()
        let originalClip = Clip(duration: .init(value: 2, timescale: 1), title: .init(text: "Life Editor", fontSize: 24, style: .init(x: 0.5, y: 0.5)))
        let original = ProjectDocument(sequence: .init(settings: .init(width: 192, height: 108), tracks: [.init(name: "Title", kind: .title, clips: [originalClip])]))
        for kind in TitleAnimationKind.allCases {
            var document = original
            document.sequence.tracks[0].clips[0].title?.animation = .init(kind: kind, duration: 1)
            let editor = ProjectEditor(document: original)
            try editor.perform(.replace(document)); editor.undo(); #expect(editor.document == original); editor.redo()
            let package = directory.appendingPathComponent(kind.rawValue + ".lifeedit")
            try ProjectPackage.write(editor.document, to: package)
            let reopened = try ProjectPackage.read(from: package)
            #expect(reopened == document)
            let snapshot = ProjectSnapshot(document: reopened)
            let prepared = try await pipeline.prepare(snapshot)
            let preview = generator(prepared.playerItem.asset, video: prepared.playerItem.videoComposition)
            let start = bytes(try await preview.image(at: .zero).image)
            let middleTime = CMTime(value: 1, timescale: 5)
            let middle = bytes(try await preview.image(at: middleTime).image)
            let stable = bytes(try await preview.image(at: CMTime(value: 3, timescale: 2)).image)
            #expect(energy(start) < 1)
            #expect(energy(middle) > 1)
            #expect(middle != stable)
            #expect(bytes(try await preview.image(at: middleTime).image) == middle)
            let output = directory.appendingPathComponent(kind.rawValue + ".mp4")
            try await pipeline.export(snapshot, to: output)
            let decoded = generator(AVURLAsset(url: output))
            for (time, expected) in [(CMTime.zero, start), (middleTime, middle), (CMTime(value: 3, timescale: 2), stable)] {
                let actual = bytes(try await decoded.image(at: time).image)
                #expect(meanDifference(actual, expected) < 5)
            }
        }
        var document = original
        document.sequence.tracks[0].clips[0].title?.animation = .init(kind: .typewriter, duration: 2)
        let before = try await pipeline.prepare(.init(document: document))
        let reference = bytes(try await generator(before.playerItem.asset, video: before.playerItem.videoComposition).image(at: CMTime(value: 9, timescale: 10)).image)
        let editor = ProjectEditor(document: document)
        try editor.perform(.trim(clipID: originalClip.id, start: .init(value: 1, timescale: 2), end: .init(value: 2, timescale: 1)))
        try editor.perform(.retime(clipID: originalClip.id, speed: 2, preservesPitch: true))
        let changed = try await pipeline.prepare(editor.snapshot)
        #expect(bytes(try await generator(changed.playerItem.asset, video: changed.playerItem.videoComposition).image(at: CMTime(value: 7, timescale: 10)).image) == reference)
    }
    private func generator(_ asset: AVAsset, video: AVVideoComposition? = nil) -> AVAssetImageGenerator {
        let result = AVAssetImageGenerator(asset: asset); result.videoComposition = video
        result.requestedTimeToleranceBefore = .zero; result.requestedTimeToleranceAfter = .zero
        return result
    }
    private func bytes(_ image: CGImage) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &result, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); return result
    }
    private func energy(_ pixels: [UInt8]) -> Double {
        stride(from: 0, to: pixels.count, by: 4).reduce(0.0) { $0 + Double(pixels[$1]) + Double(pixels[$1 + 1]) + Double(pixels[$1 + 2]) } / Double(pixels.count / 4)
    }
    private func meanDifference(_ left: [UInt8], _ right: [UInt8]) -> Double {
        zip(left, right).reduce(0.0) { $0 + Double(abs(Int($1.0) - Int($1.1))) } / Double(left.count)
    }
}
