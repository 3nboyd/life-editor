import Testing
@preconcurrency import AVFoundation
import CoreImage
import AppKit
import QuartzCore
import Darwin
import LifeCore
@testable import LifeMedia

@MainActor struct MediaPipelineTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"] == "1", "Requires native VideoToolbox encoder access; run LIFE_RUN_MEDIA_INTEGRATION=1 swift test on a local Mac."))
    func testNativeLayeredRetimedExportMatchesPreviewPlan() async throws {
        try await withDeadline(seconds: 30) { try await self.exerciseNativePipeline() }
    }

    private func exerciseNativePipeline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("life-media-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let red = directory.appendingPathComponent("red.mov")
        let blue = directory.appendingPathComponent("blue.mov")
        try await makeVideo(red, color: CIColor(red: 1, green: 0, blue: 0))
        try await makeVideo(blue, color: CIColor(red: 0, green: 0, blue: 1))
        let audioURL = directory.appendingPathComponent("tone.wav")
        try makeTone(audioURL)
        trace("fixtures ready")
        let pipeline = MediaPipeline()
        let a = try await pipeline.probe(red), b = try await pipeline.probe(blue)
        let tone = try await pipeline.probe(audioURL)
        #expect(a.width == 64); #expect(a.hasVideo); #expect(tone.hasAudio)
        trace("native probe complete")
        let native = AVAssetImageGenerator(asset: AVURLAsset(url: red))
        _ = try await native.image(at: .zero)
        trace("native raw decode complete")
        let second = RationalTime(value: 1, timescale: 1)
        let bottom = Clip(assetID: a.asset.id, duration: second)
        let top = Clip(assetID: b.asset.id, duration: second, opacity: .init(baseValue: 0.5))
        let audio = Clip(assetID: tone.asset.id, duration: second, speed: 0.5,
                         volume: .init(points: [.init(time: .zero, value: 1), .init(time: second, value: 0)]))
        let title = Clip(name: "Title", duration: second,
                         opacity: .init(points: [.init(time: .zero, value: 0), .init(time: second, value: 1)]),
                         title: .init(text: "Life", fontSize: 14))
        let document = ProjectDocument(sequence: .init(settings: .init(width: 64, height: 64), tracks: [
            .init(name: "Red", kind: .video, clips: [bottom]),
            .init(name: "Blue", kind: .video, clips: [top]),
            .init(name: "Music", kind: .audio, clips: [audio]),
            .init(name: "Title", kind: .title, clips: [title])
        ]), assets: [a.asset, b.asset, tone.asset])
        // Exercise an actual undoable edit and atomic Finder-package save, then
        // build both media paths from the reopened committed document.
        let package = directory.appendingPathComponent("Edited.lifeedit", isDirectory: true)
        try ProjectPackage.write(document, to: package)
        let editor = ProjectEditor(document: document)
        try editor.perform(.split(clipID: bottom.id, at: .init(value: 1, timescale: 2)))
        let edited = editor.document
        #expect(edited.sequence.tracks[0].clips.count == 2)
        editor.undo(); #expect(editor.document == document)
        editor.redo(); #expect(editor.document == edited)
        try ProjectPackage.write(editor.document, to: package)
        let reopened = try ProjectPackage.read(from: package)
        #expect(reopened == edited)
        let snapshot = ProjectSnapshot(document: reopened)
        let prepared = try await pipeline.prepare(snapshot)
        trace("composition prepared")
        let preview = AVAssetImageGenerator(asset: prepared.playerItem.asset)
        preview.videoComposition = prepared.playerItem.videoComposition
        let frameTime = CMTime(value: 15, timescale: 30)
        let previewFrame = try await preview.image(at: frameTime).image
        trace("shared-compositor preview complete")
        let destination = directory.appendingPathComponent("result.mp4")
        try await pipeline.export(snapshot, to: destination)
        trace("export complete")
        let exported = AVURLAsset(url: destination)
        let audioTrack = try await exported.loadTracks(withMediaType: .audio).first!
        trace("audio track range: \(try await audioTrack.load(.timeRange))")
        let duration = try await exported.load(.duration)
        #expect(abs(duration.seconds - 1) < 0.05)
        let decoder = AVAssetImageGenerator(asset: exported)
        let exportFrame = try await decoder.image(at: frameTime).image
        let p = pixel(previewFrame), e = pixel(exportFrame)
        #expect(p[0] > 80); #expect(p[2] > 80)
        #expect(p[1] < 40)
        for component in 0..<3 { #expect(abs(Int(p[component]) - Int(e[component])) < 20) }
        let samples = try await readAudio(exported)
        trace("audio samples: \(samples.count)")
        try #require(samples.count > 43200)
        let early = rms(Array(samples[2400..<9600])), late = rms(Array(samples[36000..<43200]))
        #expect(early > late * 2)
        #expect(rms(Array(samples[0..<480])) > 0.05)
        // Pitch preserving half-speed should remain near 440Hz, not varispeed's 220Hz.
        let region = Array(samples[4800..<19200])
        let crossings = zip(region, region.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
        #expect(abs(Double(crossings) / (Double(region.count) / 48000) - 440) < 35)
        var multicam = document
        multicam.sequence.multicamGroups = [.init(angleAssetIDs: [a.asset.id, b.asset.id], masterAudioAssetID: tone.asset.id,
            cuts: [.init(time: .init(value: 1, timescale: 2), angleID: b.asset.id)])]
        multicam.sequence.tracks[1].clips[0].opacity = .init(baseValue: 1)
        let switched = directory.appendingPathComponent("multicam.mp4")
        try await pipeline.export(.init(document: multicam), to: switched)
        let cameraDecoder = AVAssetImageGenerator(asset: AVURLAsset(url: switched))
        cameraDecoder.requestedTimeToleranceBefore = .zero; cameraDecoder.requestedTimeToleranceAfter = .zero
        let first = pixel(try await cameraDecoder.image(at: CMTime(value: 1, timescale: 4)).image)
        let last = pixel(try await cameraDecoder.image(at: CMTime(value: 3, timescale: 4)).image)
        #expect(first[0] > 200 && first[2] < 20)
        #expect(last[2] > 200 && last[0] < 20)
        #expect(try await readAudio(AVURLAsset(url: switched)).count > 43200)

    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"] == "1"))
    func testTitleOnlyExport() async throws {
        try await withDeadline(seconds: 15) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("life-title-\(UUID()).mp4")
            defer { try? FileManager.default.removeItem(at: url) }
            let document = ProjectDocument(sequence: .init(settings: .init(width: 64, height: 64), tracks: [
                .init(name: "Title", kind: .title, clips: [.init(duration: .init(value: 1, timescale: 1), title: .init(text: "Life\nEditor", fontSize: 14, style: .init(y: 0.5, background: .init(red: 0, green: 0, blue: 1), cornerRadius: 0.2, outlineWidth: 1)))])
            ]))
            try await MediaPipeline().export(.init(document: document), to: url)
            let asset = AVURLAsset(url: url)
            #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
            let frame = try await AVAssetImageGenerator(asset: asset).image(at: .zero).image
            var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
            let context = CGContext(data: &pixels, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 64 * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(frame, in: CGRect(x: 0, y: 0, width: 64, height: 64))
            #expect(stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 100 }.count > 20)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"] == "1"))
    func testStillImageExportAndAudioOnly() async throws {
        try await withDeadline(seconds: 15) {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("life-still-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let png = directory.appendingPathComponent("still.png")
            let context = CIContext()
            let image = context.createCGImage(CIImage(color: CIColor(red: 1, green: 0, blue: 0)), from: CGRect(x: 0, y: 0, width: 64, height: 64))!
            let bitmap = NSBitmapImageRep(cgImage: image)
            try bitmap.representation(using: .png, properties: [:])!.write(to: png)
            let pipeline = MediaPipeline()
            let probe = try await pipeline.probe(png)
            #expect(probe.asset.kind == .image)
            let document = ProjectDocument(sequence: .init(settings: .init(width: 64, height: 64), tracks: [
                .init(name: "Still", kind: .video, clips: [.init(assetID: probe.asset.id, duration: .init(value: 1, timescale: 1))])
            ]), assets: [probe.asset])
            let output = directory.appendingPathComponent("still.mp4")
            try await pipeline.export(.init(document: document), to: output)
            #expect(pixel(try await AVAssetImageGenerator(asset: AVURLAsset(url: output)).image(at: .zero).image)[0] > 200)
            let grayscale = NativeEffectRegistry.make("life.filter.grayscale")
            let thumb = pixel(try await pipeline.thumbnail(asset: probe.asset, effects: [grayscale]))
            #expect(abs(Int(thumb[0]) - Int(thumb[1])) < 3)
            var styled = document
            styled.sequence.tracks[0].clips[0].effects = [grayscale]
            let filteredOutput = directory.appendingPathComponent("filtered.mp4")
            try await pipeline.export(.init(document: try ProjectDocument.decode(styled.encoded())), to: filteredOutput)
            let filtered = pixel(try await AVAssetImageGenerator(asset: AVURLAsset(url: filteredOutput)).image(at: .zero).image)
            for channel in 0..<3 { #expect(abs(Int(filtered[channel]) - Int(thumb[channel])) < 20) }
            styled.sequence.tracks[0].clips[0].visual = .init(x: 0.8, scaleX: 0.25, scaleY: 0.25)
            let transformedOutput = directory.appendingPathComponent("transformed.mp4")
            try await pipeline.export(.init(document: styled), to: transformedOutput)
            let transformed = try await AVAssetImageGenerator(asset: AVURLAsset(url: transformedOutput)).image(at: .zero).image
            #expect(pixel(transformed)[0] < 10)
            #expect(pixel(transformed, x: 51, y: 32)[0] > 20)
            let grain = NativeEffectRegistry.make("life.filter.VHS", seed: 42)
            let repeatedA = try await pipeline.thumbnail(asset: probe.asset, at: .init(value: 1, timescale: 2), effects: [grain])
            let repeatedB = try await pipeline.thumbnail(asset: probe.asset, at: .init(value: 1, timescale: 2), effects: [grain])
            #expect(imageBytes(repeatedA) == imageBytes(repeatedB))
            #expect(imageBytes(repeatedA) != imageBytes(try await pipeline.thumbnail(asset: probe.asset)))
            for definition in NativeEffectRegistry.definitions + NativeEffectRegistry.adjustments {
                _ = try await pipeline.thumbnail(asset: probe.asset, effects: [NativeEffectRegistry.make(definition.id)])
            }

            let tone = directory.appendingPathComponent("tone.wav")
            try makeTone(tone)
            let audio = try await pipeline.probe(tone)
            let music = ProjectDocument(sequence: .init(settings: .init(width: 64, height: 64), tracks: [
                .init(name: "Music", kind: .audio, clips: [.init(assetID: audio.asset.id, duration: .init(value: 1, timescale: 1))])
            ]), assets: [audio.asset])
            let musicOutput = directory.appendingPathComponent("music.mp4")
            try await pipeline.export(.init(document: music), to: musicOutput)
            #expect(try await readAudio(AVURLAsset(url: musicOutput)).count >= 47000)
        }
    }

    @Test func testAuditionIsLocalAndDoesNotAlterStoredCuts() {
        let first = UUID(), second = UUID()
        let group = MulticamGroup(angleAssetIDs: [first, second], cuts: [.init(time: .init(value: 1, timescale: 1), angleID: second)])
        let compositor = LifeVideoCompositor()
        #expect(compositor.selectedAngle(in: group, at: .zero) == first)
        compositor.setAudition(second)
        #expect(compositor.selectedAngle(in: group, at: .zero) == second)
        #expect(LifeVideoCompositor().selectedAngle(in: group, at: .zero) == first)
        compositor.setAudition(nil)
        #expect(compositor.selectedAngle(in: group, at: .zero) == first)
        #expect(compositor.selectedAngle(in: group, at: .init(value: 1, timescale: 1)) == second)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"] == "1"))
    func testExportFormatsRangeCodecsAndCancellation() async throws {
        try await withDeadline(seconds: 30) {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("life-formats-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let toneURL = directory.appendingPathComponent("tone.wav")
            try makeTone(toneURL)
            let pipeline = MediaPipeline()
            let tone = try await pipeline.probe(toneURL)
            let second = RationalTime(value: 1, timescale: 1)
            let document = ProjectDocument(sequence: .init(settings: .init(width: 64, height: 64), tracks: [
                .init(name: "Title", kind: .title, clips: [.init(duration: second, title: .init(text: "Life", fontSize: 14))]),
                .init(name: "Audio", kind: .audio, clips: [.init(assetID: tone.asset.id, duration: second)])
            ]), assets: [tone.asset])
            for format in ExportFormat.allCases {
                let destination = directory.appendingPathComponent("\(format.rawValue).\(format.fileExtension)")
                let state = ExportTestState()
                try await pipeline.export(.init(document: document), to: destination,
                    options: .init(format: format, width: 128, height: 72, frameRate: .init(numerator: 24),
                                   rangeStart: .init(value: 1, timescale: 4), rangeDuration: .init(value: 1, timescale: 2))) { state.values.append($0) }
                #expect(state.values.first == 0 && state.values.last == 1)
                #expect(zip(state.values, state.values.dropFirst()).allSatisfy { $0 <= $1 })
                let result = AVURLAsset(url: destination)
                #expect(abs(try await result.load(.duration).seconds - 0.5) < 0.04)
                let video = try await result.loadTracks(withMediaType: .video)
                #expect(video.count == (format.hasVideo ? 1 : 0))
                if let video = video.first {
                    let size = try await video.load(.naturalSize)
                    #expect(size.width == 128 && size.height == 72)
                    let codec = CMFormatDescriptionGetMediaSubType(try await video.load(.formatDescriptions)[0])
                    let expected = format == .h264 ? kCMVideoCodecType_H264 : format == .hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_AppleProRes422
                    #expect(codec == expected)
                }
                let audio = try await result.loadTracks(withMediaType: .audio)
                let description = try await audio[0].load(.formatDescriptions)[0]
                let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description)!.pointee
                #expect(stream.mSampleRate == 48000 && stream.mChannelsPerFrame == 2)
                #expect(stream.mFormatID == (format == .wav || format == .aiff ? kAudioFormatLinearPCM : kAudioFormatMPEG4AAC))
                #expect(try await readAudio(result).count >= 23000)
            }
            let existing = directory.appendingPathComponent("existing.mp4")
            let original = Data("preserve existing export".utf8)
            try original.write(to: existing)
            var long = document
            long.sequence.tracks[0].clips[0].duration = .init(value: 10, timescale: 1)
            let cancellation = ExportTestState()
            let snapshot = ProjectSnapshot(document: long)
            cancellation.job = Task {
                try await pipeline.export(snapshot, to: existing, options: .init(width: 1920, height: 1080)) { value in
                    if value > 0 { cancellation.job?.cancel() }
                }
            }
            do { try await cancellation.job!.value; Issue.record("Cancelled export must throw") }
            catch is CancellationError { }
            #expect(try Data(contentsOf: existing) == original)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.hasPrefix(".life-export-") })
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"] == "1" && ProcessInfo.processInfo.environment["LIFE_HELPER_DIRECTORY"] != nil))
    func testPinnedHelperConversionAndCancellation() async throws {
        try await withDeadline(seconds: 30) {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("life-helper-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let helper = try #require(MediaHelpers.directory)
            let original = directory.appendingPathComponent("unsupported.mkv")
            let raw = directory.appendingPathComponent("red.rgb")
            var rawBytes = Data(count: 64 * 64 * 3 * 30)
            rawBytes.withUnsafeMutableBytes { bytes in
                let channels = bytes.bindMemory(to: UInt8.self)
                for offset in stride(from: 0, to: channels.count, by: 3) { channels[offset] = 255 }
            }
            try rawBytes.write(to: raw)
            let toneFixture = directory.appendingPathComponent("tone.wav")
            try makeTone(toneFixture)
            let fixture = Process()
            fixture.executableURL = helper.appendingPathComponent("ffmpeg")
            fixture.arguments = ["-v", "error", "-nostdin", "-f", "rawvideo", "-pixel_format", "rgb24", "-video_size", "64x64", "-framerate", "30", "-i", raw.path,
                "-i", toneFixture.path, "-c:v", "ffv1", "-c:a", "pcm_s16le", original.path]
            try fixture.run(); fixture.waitUntilExit()
            try #require(fixture.terminationStatus == 0)
            let bytes = try Data(contentsOf: original)
            let pipeline = MediaPipeline()
            let result = try await pipeline.probe(original)
            let prepared = try #require(result.asset.preparedURL)
            defer {
                try? FileManager.default.removeItem(at: prepared)
                try? FileManager.default.removeItem(at: prepared.deletingPathExtension().appendingPathExtension("probe.json"))
            }
            #expect(result.asset.url == original)
            #expect(result.width == 64 && result.height == 64 && result.hasAudio)
            #expect(prepared.path.contains("Application Support/Life Editor/Intermediates"))
            #expect(FileManager.default.fileExists(atPath: prepared.deletingPathExtension().appendingPathExtension("probe.json").path))
            #expect(pixel(try await pipeline.thumbnail(asset: result.asset))[0] > 200)
            let document = ProjectDocument(sequence: .init(settings: .init(width: 64, height: 64), tracks: [
                .init(name: "Converted", kind: .video, clips: [.init(assetID: result.asset.id, duration: .init(value: 1, timescale: 1))])
            ]), assets: [result.asset])
            let output = directory.appendingPathComponent("converted.mp4")
            try await pipeline.export(.init(document: try ProjectDocument.decode(document.encoded())), to: output)
            #expect(pixel(try await AVAssetImageGenerator(asset: AVURLAsset(url: output)).image(at: .zero).image)[0] > 200)
            let normalSamples = try await readAudio(AVURLAsset(url: output))
            #expect(normalSamples.count >= 47000)
            var detached = document
            detached.sequence.tracks[0].clips[0].audioEnabled = false
            detached.sequence.tracks.append(.init(name: "Detached", kind: .audio, clips: [.init(assetID: result.asset.id, duration: .init(value: 1, timescale: 1))]))
            let detachedOutput = directory.appendingPathComponent("detached.mp4")
            try await pipeline.export(.init(document: detached), to: detachedOutput)
            let detachedSamples = try await readAudio(AVURLAsset(url: detachedOutput))
            #expect(abs(rms(normalSamples) - rms(detachedSamples)) < 0.01)
            let copy = directory.appendingPathComponent("cancelled.mkv")
            try bytes.write(to: copy)
            let cancellation = ExportTestState()
            cancellation.job = Task {
                _ = try await pipeline.probe(copy) { _ in cancellation.job?.cancel() }
            }
            do { try await cancellation.job!.value; Issue.record("Cancelled preparation must throw") }
            catch is CancellationError { }
            #expect(try Data(contentsOf: copy) == bytes)
            #expect(try FileManager.default.contentsOfDirectory(atPath: prepared.deletingLastPathComponent().path).allSatisfy { !$0.hasPrefix(".prepare-") })
            do { _ = try await pipeline.probe(URL(string: "https://example.com/video.mp4")!); Issue.record("Network import must be rejected") }
            catch HelperError.localFilesOnly { }
            let playlist = directory.appendingPathComponent("network.m3u8")
            try "#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\nhttps://example.com/chunk.ts\n#EXT-X-ENDLIST\n".write(to: playlist, atomically: true, encoding: .utf8)
            do { _ = try await MediaHelpers.prepare(playlist, progress: nil); Issue.record("Network protocols in local playlists must fail") }
            catch HelperError.failed { }
            if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") {
                let webm = directory.appendingPathComponent("vp9.webm")
                let encoder = Process(); encoder.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
                encoder.arguments = ["-v", "error", "-nostdin", "-f", "lavfi", "-i", "color=c=blue:s=64x64:r=30:d=1", "-c:v", "libvpx-vp9", webm.path]
                try encoder.run(); encoder.waitUntilExit()
                try #require(encoder.terminationStatus == 0)
                let camera = try await pipeline.probe(webm)
                if let intermediate = camera.asset.preparedURL {
                    defer { try? FileManager.default.removeItem(at: intermediate); try? FileManager.default.removeItem(at: intermediate.deletingPathExtension().appendingPathExtension("probe.json")) }
                    #expect(pixel(try await pipeline.thumbnail(asset: camera.asset))[2] > 200)
                } else { #expect(pixel(try await pipeline.thumbnail(asset: camera.asset))[2] > 200) }
            }
        }
    }

    @Test func testCacheCleanupOnlyDeletesOwnedUnprotectedArtifacts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("life-cache-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("org.lifeeditor.proxy")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let disposable = directory.appendingPathComponent(String(repeating: "a", count: 64) + ".mp4")
        let protected = directory.appendingPathComponent(String(repeating: "b", count: 64) + ".mp4")
        let leased = directory.appendingPathComponent(String(repeating: "c", count: 64) + ".mp4")
        let original = directory.appendingPathComponent("Original.mov")
        let intermediate = root.appendingPathComponent("Intermediates/source.mov")
        try FileManager.default.createDirectory(at: intermediate.deletingLastPathComponent(), withIntermediateDirectories: true)
        for url in [disposable, protected, leased, original, intermediate] { try Data(repeating: 1, count: 100).write(to: url) }
        let link = directory.appendingPathComponent(String(repeating: "d", count: 64) + ".mov")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        let lease = CacheLease([leased])
        defer { withExtendedLifetime(lease) {} }
        let cache = CacheStorage(root: root)
        #expect(try cache.usageBytes() == 300)
        #expect(try cache.cleanup(budget: 0, protectedURLs: [protected]) == 200)
        #expect(!FileManager.default.fileExists(atPath: disposable.path))
        for url in [protected, leased, original, intermediate, link] { #expect(FileManager.default.fileExists(atPath: url.path)) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"] == "1"))
    func testProxyAndFourSynchronizedPlayers() async throws {
        try await withDeadline(seconds: 30) {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("life-proxy-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = directory.appendingPathComponent("source.mov")
            try await makeVideo(source, color: CIColor(red: 1, green: 0, blue: 0), width: 1280, height: 720, frames: 60, changesHalfway: true)
            let pipeline = MediaPipeline()
            let media = try await pipeline.probe(source)
            let low = try await pipeline.proxy(asset: media.asset, maxDimension: 320)
            let proxy = try await pipeline.proxy(asset: media.asset, maxDimension: 1280)
            defer { try? FileManager.default.removeItem(at: low); try? FileManager.default.removeItem(at: proxy) }
            #expect(low != proxy)
            let sourceBytes = try Data(contentsOf: source)
            let cancellation = ExportTestState()
            cancellation.job = Task {
                _ = try await pipeline.proxy(asset: media.asset, maxDimension: 640) { _ in cancellation.job?.cancel() }
            }
            do { try await cancellation.job!.value; Issue.record("Cancelled proxy must throw") }
            catch is CancellationError { }
            #expect(try Data(contentsOf: source) == sourceBytes)
            #expect(try await pipeline.proxy(asset: media.asset, maxDimension: 1280) == proxy)
            let reduced = AVURLAsset(url: low)
            let lowTrack = try await reduced.loadTracks(withMediaType: .video)[0]
            #expect(try await lowTrack.load(.naturalSize) == CGSize(width: 320, height: 180))
            #expect(abs(try await reduced.load(.duration).seconds - 2) < 0.001)
            let generator = AVAssetImageGenerator(asset: reduced)
            generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
            let before = try await generator.image(at: CMTime(value: 1, timescale: 2))
            let after = try await generator.image(at: CMTime(value: 3, timescale: 2))
            #expect(abs(before.actualTime.seconds - 0.5) < 0.034)
            #expect(abs(after.actualTime.seconds - 1.5) < 0.034)
            // Draw scaled frames into the existing sample helper's 64px canvas.
            #expect(pixel(before.image)[0] > 200 && pixel(after.image)[2] > 200)
            let document = ProjectDocument(sequence: .init(settings: .init(width: 1280, height: 720), tracks: [
                .init(name: "Video", kind: .video, clips: [.init(assetID: media.asset.id, duration: .init(value: 2, timescale: 1))])
            ]), assets: [media.asset])
            let prepared = try await pipeline.prepare(.init(document: document), useProxies: true)
            #expect(prepared.usesProxies)
            let exported = directory.appendingPathComponent("original-resolution.mp4")
            try await pipeline.export(.init(document: document), to: exported)
            #expect(try await AVURLAsset(url: exported).loadTracks(withMediaType: .video)[0].load(.naturalSize) == CGSize(width: 1280, height: 720))
            let started = Date()
            var initialUsage = rusage()
            getrusage(RUSAGE_SELF, &initialUsage)
            var players: [AVPlayer] = []
            var outputs: [AVPlayerItemVideoOutput] = []
            for _ in 0..<4 {
                let item = AVPlayerItem(url: proxy)
                let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                item.add(output); outputs.append(output)
                pipeline.keepCacheFiles([proxy], on: item)
                let player = AVPlayer(playerItem: item); player.isMuted = true; player.automaticallyWaitsToMinimizeStalling = false
                players.append(player)
            }
            defer { for player in players { player.pause() } }
            for _ in 0..<400 {
                if players.allSatisfy({ $0.currentItem?.status == .readyToPlay }) { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(players.allSatisfy { $0.currentItem?.status == .readyToPlay })
            let host = CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()), CMTime(value: 1, timescale: 4))
            for player in players { player.setRate(1, time: .zero, atHostTime: host) }
            var decoded = [Int](repeating: 0, count: 4)
            for _ in 0..<60 {
                let now = CACurrentMediaTime()
                for (index, output) in outputs.enumerated() {
                    let time = output.itemTime(forHostTime: now)
                    if output.hasNewPixelBuffer(forItemTime: time), let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                        #expect(CVPixelBufferGetWidth(buffer) == 1280 && CVPixelBufferGetHeight(buffer) == 720)
                        decoded[index] += 1
                    }
                }
                try await Task.sleep(for: .milliseconds(16))
            }
            #expect(decoded.allSatisfy { $0 > 5 })
            let positions = players.map { $0.currentTime().seconds }
            #expect((positions.max()! - positions.min()!) < 0.04)
            var finalUsage = rusage()
            getrusage(RUSAGE_SELF, &finalUsage)
            func cpu(_ usage: rusage) -> Double {
                Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
            }
            var name = [CChar](repeating: 0, count: 256)
            var length = name.count
            sysctlbyname("machdep.cpu.brand_string", &name, &length, nil, 0)
            trace("four1280x720 muted AVPlayers decoded=\(decoded), elapsed=\(Date().timeIntervalSince(started))s, positionSpread=\(positions.max()! - positions.min()!)s, cpuSeconds=\(cpu(finalUsage) - cpu(initialUsage)), processPeakRSSBytes=\(finalUsage.ru_maxrss), hardware=\(String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)), RAMBytes=\(ProcessInfo.processInfo.physicalMemory); no M1/performance-target claim")
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"] == "1"))
    func testGraphicsEditSaveReopenPreviewAndExport() async throws {
        try await withDeadline(seconds: 15) {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("life-graphics-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let shape = GraphicContent.shape(.init(kind: .rectangle, rect: .init(x: 0.2, y: 0.2, width: 0.3, height: 0.4),
                fill: .init(red: 1, green: 0, blue: 0), stroke: .clear, strokeWidth: 0))
            let drawing = GraphicContent.drawing(.init(strokes: [.init(points: [.init(x: 0.1, y: 0.8), .init(x: 0.9, y: 0.8)],
                color: .init(red: 0, green: 0, blue: 1), width: 0.08)]))
            let initial = ProjectDocument(sequence: .init(settings: .init(width: 64, height: 64)))
            let editor = ProjectEditor(document: initial)
            var edited = initial
            edited.sequence.tracks = [
                .init(name: "Shape", kind: .shape, clips: [.init(name: "Rectangle", duration: .init(value: 1, timescale: 1), graphic: shape)]),
                .init(name: "Drawing", kind: .drawing, clips: [.init(name: "Pen", start: .init(value: 1, timescale: 4), duration: .init(value: 1, timescale: 2), graphic: drawing)])
            ]
            try editor.perform(.replace(edited))
            editor.undo(); #expect(editor.document == initial)
            editor.redo(); #expect(editor.document == edited)
            let package = directory.appendingPathComponent("Graphics.lifeedit")
            try ProjectPackage.write(editor.document, to: package)
            let reopened = try ProjectPackage.read(from: package)
            #expect(reopened == edited)
            let pipeline = MediaPipeline()
            let snapshot = ProjectSnapshot(document: reopened)
            let preview = try await pipeline.prepare(snapshot)
            let generator = AVAssetImageGenerator(asset: preview.playerItem.asset)
            generator.videoComposition = preview.playerItem.videoComposition
            generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
            let reference = try await generator.image(at: CMTime(value: 1, timescale: 2)).image
            #expect(pixel(reference, x: 20, y: 40)[0] > 200)
            #expect(pixel(reference, x: 32, y: 13)[2] > 200)
            #expect(pixel(reference, x: 55, y: 40)[0] < 10)
            let output = directory.appendingPathComponent("graphics.mp4")
            try await pipeline.export(snapshot, to: output)
            let decoder = AVAssetImageGenerator(asset: AVURLAsset(url: output))
            decoder.requestedTimeToleranceBefore = .zero; decoder.requestedTimeToleranceAfter = .zero
            let actual = try await decoder.image(at: CMTime(value: 1, timescale: 2)).image
            for point in [(20.0, 40.0), (32.0, 13.0), (55.0, 40.0)] {
                let expectedPixel = pixel(reference, x: point.0, y: point.1), actualPixel = pixel(actual, x: point.0, y: point.1)
                for channel in 0..<3 { #expect(abs(Int(expectedPixel[channel]) - Int(actualPixel[channel])) < 20) }
            }
            #expect(pixel(try await decoder.image(at: CMTime(value: 1, timescale: 10)).image, x: 32, y: 13)[2] < 10)
            #expect(pixel(try await decoder.image(at: CMTime(value: 9, timescale: 10)).image, x: 32, y: 13)[2] < 10)
        }
    }

    @Test func testAllTransitionGraphsAreDeterministicAndReachEndpoints() throws {
        let canvas = CGRect(x: 0, y: 0, width: 64, height: 64)
        let left = CIFilter(name: "CILinearGradient", parameters: ["inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 64, y: 64),
            "inputColor0": CIColor(red: 1, green: 0, blue: 0), "inputColor1": CIColor(red: 1, green: 1, blue: 0)])!.outputImage!.cropped(to: canvas)
        let right = CIFilter(name: "CILinearGradient", parameters: ["inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 64, y: 64),
            "inputColor0": CIColor(red: 0, green: 0, blue: 1), "inputColor1": CIColor(red: 0, green: 1, blue: 1)])!.outputImage!.cropped(to: canvas)
        let context = CIContext()
        func bytes(_ image: CIImage) -> [UInt8] { imageBytes(context.createCGImage(image, from: canvas)!) }
        let original = bytes(left), destination = bytes(right)
        var versions = Set<Data>()
        let seed = UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")!
        for kind in TransitionKind.allCases {
            let transition = VideoTransition(id: seed, kind: kind, trackID: UUID(), leftClipID: UUID(), rightClipID: UUID(),
                duration: .init(value: 2, timescale: 5), color: .init(red: 0, green: 1, blue: 0))
            func frame(_ progress: Double) -> CIImage { TransitionRenderer.image(from: left, to: right, transition: transition, progress: progress, canvas: canvas) }
            #expect(bytes(frame(0)) == original)
            #expect(bytes(frame(1)) == destination)
            let first = bytes(frame(0.37))
            #expect(first == bytes(frame(0.37)))
            #expect(first != original && first != destination)
            versions.insert(Data(first))
        }
        #expect(versions.count >= 12)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"] == "1"))
    func testAllNativeTransitionsPreserveTimingAndMatchExport() async throws {
        try await withDeadline(seconds: 45) {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("life-transitions-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let redURL = directory.appendingPathComponent("red.mov"), blueURL = directory.appendingPathComponent("blue.mov")
            try await makeVideo(redURL, color: CIColor(red: 1, green: 0, blue: 0), frames: 60)
            try await makeVideo(blueURL, color: CIColor(red: 0, green: 0, blue: 1), frames: 60)
            let pipeline = MediaPipeline()
            let red = try await pipeline.probe(redURL), blue = try await pipeline.probe(blueURL)
            let left = Clip(assetID: red.asset.id, duration: .init(value: 1, timescale: 1), sourceStart: .init(value: 1, timescale: 4))
            let right = Clip(assetID: blue.asset.id, start: .init(value: 1, timescale: 1), duration: .init(value: 1, timescale: 1), sourceStart: .init(value: 1, timescale: 4))
            let track = Track(name: "Cut", kind: .video, clips: [left, right])
            let lower = Track(name: "Lower", kind: .shape, clips: [.init(duration: .init(value: 2, timescale: 1),
                graphic: .shape(.init(kind: .rectangle, rect: .init(x: 0, y: 0, width: 1, height: 1), fill: .init(red: 0, green: 1, blue: 0), strokeWidth: 0)))])
            let original = ProjectDocument(sequence: .init(settings: .init(width: 64, height: 64), tracks: [lower, track]), assets: [red.asset, blue.asset])
            for kind in TransitionKind.allCases {
                var document = original
                document.sequence.transitions = [.init(kind: kind, trackID: track.id, leftClipID: left.id, rightClipID: right.id,
                    duration: .init(value: 2, timescale: 5), color: .init(red: 0, green: 1, blue: 0))]
                let editor = ProjectEditor(document: original)
                try editor.perform(.replace(document)); editor.undo(); #expect(editor.document == original); editor.redo()
                let package = directory.appendingPathComponent("\(kind.rawValue).lifeedit")
                try ProjectPackage.write(editor.document, to: package)
                let reopened = try ProjectPackage.read(from: package)
                #expect(reopened == document)
                let snapshot = ProjectSnapshot(document: reopened)
                let prepared = try await pipeline.prepare(snapshot)
                let preview = AVAssetImageGenerator(asset: prepared.playerItem.asset)
                preview.videoComposition = prepared.playerItem.videoComposition
                preview.requestedTimeToleranceBefore = .zero; preview.requestedTimeToleranceAfter = .zero
                let frame = try await preview.image(at: CMTime(value: 1, timescale: 1)).image
                let expected = pixel(frame)
                if kind == .crossDissolve { #expect(expected[0] > 100 && expected[2] > 100 && expected[1] < 20) }
                if kind == .fadeBlack { #expect(expected[0] < 10 && expected[2] < 10) }
                if kind == .fadeWhite { #expect(expected[0] > 240 && expected[2] > 240) }
                if kind == .dipColor { #expect(expected[1] > 240 && expected[0] < 10) }
                let output = directory.appendingPathComponent("\(kind.rawValue).mp4")
                try await pipeline.export(snapshot, to: output)
                let asset = AVURLAsset(url: output)
                #expect(abs(try await asset.load(.duration).seconds - 2) < 0.001)
                let decoder = AVAssetImageGenerator(asset: asset)
                decoder.requestedTimeToleranceBefore = .zero; decoder.requestedTimeToleranceAfter = .zero
                let actual = pixel(try await decoder.image(at: CMTime(value: 1, timescale: 1)).image)
                for channel in 0..<3 { #expect(abs(Int(actual[channel]) - Int(expected[channel])) < 25) }
                #expect(pixel(try await decoder.image(at: CMTime(value: 1, timescale: 2)).image)[0] > 200)
                #expect(pixel(try await decoder.image(at: CMTime(value: 3, timescale: 2)).image)[2] > 200)
            }
            var translucent = original
            translucent.sequence.tracks[1].clips[0].opacity = .init(baseValue: 0.5)
            translucent.sequence.tracks[1].clips[1].opacity = .init(baseValue: 0.5)
            translucent.sequence.transitions = [.init(kind: .crossDissolve, trackID: track.id, leftClipID: left.id, rightClipID: right.id, duration: .init(value: 2, timescale: 5))]
            let transparentOutput = directory.appendingPathComponent("lower-layers.mp4")
            try await pipeline.export(.init(document: translucent), to: transparentOutput)
            let lowerPixel = pixel(try await AVAssetImageGenerator(asset: AVURLAsset(url: transparentOutput)).image(at: CMTime(value: 1, timescale: 1)).image)
            #expect(lowerPixel[1] > 150 && lowerPixel[0] > 100 && lowerPixel[2] > 100)
            var invalid = original
            invalid.sequence.transitions = [.init(kind: .crossDissolve, trackID: track.id, leftClipID: left.id, rightClipID: right.id, duration: .init(value: 1, timescale: 1))]
            #expect(TransitionResolver.resolve(invalid.sequence.transitions![0], in: invalid) == nil)
            let invalidOutput = directory.appendingPathComponent("invalid-handles.mp4")
            try await pipeline.export(.init(document: invalid), to: invalidOutput)
            #expect(abs(try await AVURLAsset(url: invalidOutput).load(.duration).seconds - 2) < 0.001)
        }
    }

    @Test func testExportCannotReplaceOriginalMedia() async throws {
        let original = FileManager.default.temporaryDirectory.appendingPathComponent("life-original-\(UUID()).mp4")
        let bytes = Data("original media".utf8)
        try bytes.write(to: original)
        defer { try? FileManager.default.removeItem(at: original) }
        let document = ProjectDocument(assets: [.init(url: original, kind: .video, duration: .zero)])
        do {
            try await MediaPipeline().export(.init(document: document), to: original)
            Issue.record("Export should reject an original-media destination")
        } catch MediaError.protectsOriginal { }
        #expect(try Data(contentsOf: original) == bytes)
    }

    @Test func testTrimmedEnvelopeUsesOriginalCurveAndHoldBoundaries() {
        let input = AVMutableAudioMixInputParameters()
        let envelope = AutomationEnvelope(baseValue: 0.5, points: [
            .init(time: .zero, value: 0, interpolation: .hold),
            .init(time: RationalTime(value: 1, timescale: 1), value: 0.75),
            .init(time: RationalTime(value: 2, timescale: 1), value: 1)
        ], evaluationOffset: RationalTime(value: 1, timescale: 2))
        MediaPipeline.applyEnvelope(envelope, to: input, start: RationalTime(value: 3, timescale: 1),
                                    duration: RationalTime(value: 1, timescale: 1))
        var from: Float = -1, to: Float = -1
        var range = CMTimeRange.invalid
        #expect(input.getVolumeRamp(for: CMTime(value: 13, timescale: 4), startVolume: &from, endVolume: &to, timeRange: &range))
        #expect(from == 0)
        #expect(input.getVolumeRamp(for: CMTime(value: 15, timescale: 4), startVolume: &from, endVolume: &to, timeRange: &range))
        #expect(abs(from - 0.375) < 0.001)
        #expect(abs(to - 0.4375) < 0.001)
        #expect(abs(range.start.seconds - 3.5) < 0.00001)
    }

    private func trace(_ message: String) {
        FileHandle.standardError.write(Data("[LifeMedia integration] \(message)\n".utf8))
    }
    private func makeVideo(_ url: URL, color: CIColor, width: Int = 64, height: Int = 64, frames: Int = 30, changesHalfway: Bool = false) async throws {
        // Optional developer fixture helper only; no FFmpeg dependency is linked or shipped.
        // Raw frames avoid relying on an encoder merely to exercise the decoder/compositor.
        let ffmpegURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        if width == 64 && height == 64 && frames == 30 && !changesHalfway && FileManager.default.isExecutableFile(atPath: ffmpegURL.path) {
            let process = Process()
            process.executableURL = ffmpegURL
            let rgb = color.red > 0.5 ? "red" : "blue"
            process.arguments = ["-v", "error", "-nostdin", "-f", "lavfi", "-i", "color=c=\(rgb):s=64x64:r=30:d=1",
                                 "-c:v", "rawvideo", "-pix_fmt", "argb", "-y", url.path]
            try process.run(); process.waitUntilExit()
            try #require(process.terminationStatus == 0)
            return
        }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                         kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        writer.add(input); guard writer.startWriting() else { throw writer.error! }; writer.startSession(atSourceTime: .zero)
        let context = CIContext()
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
            var buffer: CVPixelBuffer?
            try #require(CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer) == kCVReturnSuccess)
            context.render(CIImage(color: changesHalfway && frame >= frames / 2 ? CIColor(red: 0, green: 0, blue: 1) : color).cropped(to: CGRect(x: 0, y: 0, width: width, height: height)), to: buffer!)
            try #require(adaptor.append(buffer!, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished(); await writer.finishWriting()
        try #require(writer.status == .completed)
    }
    private func makeTone(_ url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
        buffer.frameLength = 48000
        for i in 0..<48000 { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 440 / 48000)) * 0.5 }
        try file.write(from: buffer)
    }
    private func pixel(_ image: CGImage, x: Double = 32, y: Double = 32) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -y, width: 64, height: 64))
        return bytes
    }
    private func imageBytes(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }
    private func readAudio(_ asset: AVAsset) async throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        let track = try await asset.loadTracks(withMediaType: .audio).first!
        let output = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
        reader.add(output); try #require(reader.startReading())
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            let description = CMSampleBufferGetFormatDescription(buffer)!
            if samples.isEmpty { trace("decoded format: \(CMAudioFormatDescriptionGetStreamBasicDescription(description)!.pointee)") }
            let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
            var chunk = [Float](repeating: 0, count: count)
            _ = chunk.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * 4, destination: $0.baseAddress!) }
            samples += chunk
        }
        #expect(reader.status == .completed)
        return samples
    }
    private func rms(_ samples: [Float]) -> Double {
        sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count))
    }
}

private enum IntegrationTimeout: Error { case nativeMediaDidNotRespond }
/// A watchdog leaves a stalled AVFoundation request behind rather than hanging the test runner.
/// Production jobs remain cancellable independently. This wrapper is only for opt-in integration.
private final class DeadlineState: @unchecked Sendable {
    let lock = NSLock()
    var continuation: CheckedContinuation<Void, any Error>?
    var task: Task<Void, Never>?
    func finish(_ result: Result<Void, any Error>) {
        lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
        pending?.resume(with: result)
    }
    func timeout() {
        lock.lock(); let operation = task; lock.unlock()
        operation?.cancel()
        finish(.failure(IntegrationTimeout.nativeMediaDidNotRespond))
    }
}
@MainActor private func withDeadline(seconds: Double, operation: @escaping @MainActor @Sendable () async throws -> Void) async throws {
    let state = DeadlineState()
    try await withCheckedThrowingContinuation { continuation in
        state.continuation = continuation
        state.task = Task { @MainActor in
            do { try await operation(); state.finish(.success(())) }
            catch { state.finish(.failure(error)) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { state.timeout() }
    }
}

@MainActor private final class ExportTestState {
    var values: [Double] = []
    var job: Task<Void, any Error>?
}
