import Foundation
@preconcurrency import AVFoundation
import AppKit
import CoreImage
import CoreText
import CryptoKit
import LifeCore

public struct MediaProbe: Sendable {
    public let asset: MediaAsset
    public let width: Int
    public let height: Int
    public let frameRate: Double
    public let hasVideo: Bool
    public let hasAudio: Bool
}

public enum MediaError: LocalizedError {
    case unsupported(String), missingAsset(UUID), emptySequence, exportUnavailable, invalidRange(String), protectsOriginal
    public var errorDescription: String? {
        switch self {
        case .unsupported(let name): return "Cannot decode \(name) with the installed native codecs."
        case .missingAsset(let id): return "Media is missing (\(id)). Relink the original file."
        case .emptySequence: return "Add media or a title before playback or export."
        case .exportUnavailable: return "The selected output settings are unavailable with the installed encoders."
        case .protectsOriginal: return "Choose a different export file to preserve your original media."
        case .invalidRange(let name): return "\(name) extends beyond the original recording. Trim it or choose an explicit extension."
        }
    }
}

public struct PreparedPlayback {
    public let playerItem: AVPlayerItem
    public let usesProxies: Bool
}

extension RationalTime {
    var cmTime: CMTime { CMTime(value: value, timescale: CMTimeScale(clamping: timescale)) }
}

/// Main-actor orchestration; rendering receives immutable plans and runs off the UI thread.
@MainActor public final class MediaPipeline {
    private let audioPlans = NSMapTable<AVPlayerItem, AudioRoutingPlan>(keyOptions:.weakMemory,valueOptions:.strongMemory)
    public init() {}

    public static var helpersAvailable: Bool { MediaHelpers.directory != nil }

    public func probe(_ url: URL, progress: (@MainActor @Sendable (Double) -> Void)? = nil) async throws -> MediaProbe {
        guard url.isFileURL else { throw HelperError.localFilesOnly }
        do { return try await nativeProbe(url) }
        catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            let preparedURL = try await MediaHelpers.prepare(url, progress: progress)
            let prepared = try await nativeProbe(preparedURL)
            var reference = prepared.asset
            reference.url = url; reference.preparedURL = preparedURL
            return MediaProbe(asset: reference, width: prepared.width, height: prepared.height,
                              frameRate: prepared.frameRate, hasVideo: prepared.hasVideo, hasAudio: prepared.hasAudio)
        }
    }

    private func nativeProbe(_ url: URL) async throws -> MediaProbe {
        try Task.checkCancellation()
        if let dimensions=StillImage.dimensions(url) {
            return MediaProbe(asset: MediaAsset(url: url, kind: .image, duration: .init(value: 5, timescale: 1)),
                              width: dimensions.width, height: dimensions.height, frameRate: 0, hasVideo: false, hasAudio: false)
        }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard duration.isNumeric, duration.seconds > 0 else { throw MediaError.unsupported(url.lastPathComponent) }
        let video = try await asset.loadTracks(withMediaType: .video).first
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        guard video != nil || audio != nil else { throw MediaError.unsupported(url.lastPathComponent) }
        var width = 0, height = 0
        var rate = 0.0
        if let video {
            let size = try await video.load(.naturalSize)
            let transform = try await video.load(.preferredTransform)
            let rect = CGRect(origin: .zero, size: size).applying(transform)
            width = Int(abs(rect.width)); height = Int(abs(rect.height))
            rate = Double(try await video.load(.nominalFrameRate))
        }
        guard try await asset.load(.isPlayable) else { throw MediaError.unsupported(url.lastPathComponent) }
        if video != nil {
            let decoder = AVAssetImageGenerator(asset: asset)
            decoder.maximumSize = CGSize(width: 32, height: 32)
            _ = try await decoder.image(at: .zero)
        }
        try Task.checkCancellation()
        let media = MediaAsset(url: url, kind: video == nil ? .audio : .video,
                               duration: RationalTime(value: duration.value, timescale: Int64(duration.timescale)))
        return MediaProbe(asset: media, width: width, height: height, frameRate: rate,
                          hasVideo: video != nil, hasAudio: audio != nil)
    }

    public func thumbnail(asset: MediaAsset, at time: RationalTime = .zero, effects: [EffectInstance] = []) async throws -> CGImage {
        let source: CIImage
        if asset.kind == .image, let image = StillImage.thumbnail(asset.preparedURL ?? asset.url) { source = image }
        else {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: asset.preparedURL ?? asset.url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 180)
            generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
            source = CIImage(cgImage: try await generator.image(at: time.cmTime).image)
        }
        let result = EffectRenderer.apply(effects, to: source, time: time, sourceTime:time)
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                                          .outputColorSpace: CGColorSpace(name: CGColorSpace.itur_709)!])
        guard let image = context.createCGImage(result, from: result.extent) else { throw MediaError.unsupported(asset.url.lastPathComponent) }
        return image
    }

    public func prepare(_ snapshot: ProjectSnapshot, useProxies: Bool = false) async throws -> PreparedPlayback {
        var proxies: [UUID: URL] = [:]
        var leases: [CacheLease] = []
        defer { withExtendedLifetime(leases) {} }
        if useProxies {
            for asset in snapshot.document.assets where asset.kind == .video {
                do {
                    let url = try await proxy(asset: asset, maxDimension: 1920)
                    proxies[asset.id] = url; leases.append(CacheLease([url]))
                } catch {
                    try Task.checkCancellation()
                    // A full cache or unavailable proxy encoder must not block
                    // editing a source that the native decoder can already read.
                }
            }
        }
        let plan = try await compile(snapshot, proxies: proxies,allowAudition:true)
        let item = AVPlayerItem(asset: plan.composition)
        item.videoComposition = plan.video
        item.audioMix = plan.audio
        audioPlans.setObject(AudioRoutingPlan(routes:plan.audioRoutes),forKey:item)
        retainCacheLease(CacheLease(plan.cacheURLs), on: item)
        _ = try? CacheStorage().cleanup(protectedURLs: Set(snapshot.document.assets.flatMap { [$0.url, $0.preparedURL].compactMap { $0 } }))
        return PreparedPlayback(playerItem: item, usesProxies: !proxies.isEmpty)
    }

    public func measure(_ snapshot: ProjectSnapshot, progress: (@MainActor @Sendable (Double) -> Void)? = nil) async throws -> AudioMeasurement {
        try await scanAudio(snapshot, interval: 0.05, progress: progress).measurement
    }
    public func audioMeterFrames(_ snapshot: ProjectSnapshot, interval: Double = 0.05,
                                 progress: (@MainActor @Sendable (Double) -> Void)? = nil) async throws -> [AudioMeterFrame] {
        try await scanAudio(snapshot, interval: interval, progress: progress).meters
    }
    private func scanAudio(_ snapshot: ProjectSnapshot, interval: Double,
                           progress: (@MainActor @Sendable (Double) -> Void)?) async throws -> AudioScanResult {
        guard interval.isFinite, (0.02...1).contains(interval) else { throw MediaError.unsupported("Meter interval") }
        var identity = try snapshot.document.encoded()
        identity.append(Data("audio-scan-v1|\(interval)".utf8))
        for asset in snapshot.document.assets {
            let url = asset.preparedURL ?? asset.url
            let metadata = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            identity.append(Data("\(url.path)|\(metadata?.fileSize ?? 0)|\(metadata?.contentModificationDate?.timeIntervalSince1970 ?? 0)".utf8))
        }
        let key = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        if let cached = await AudioMeasurementCache.shared.get(key) { progress?(1); return cached }
        let compiled = try await compile(snapshot)
        let lease = CacheLease(compiled.cacheURLs)
        defer { withExtendedLifetime(lease) {} }
        let plan = ExportRenderPlan(composition: compiled.composition, video: compiled.video, audio: compiled.audio)
        progress?(0)
        let job = Task.detached(priority: .utility) { try await AudioScan.run(plan, interval: interval, progress: progress) }
        let result = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
        await AudioMeasurementCache.shared.put(result, key: key)
        return result
    }

    /// Regenerable, full-duration editing copy. Export never reads this URL from
    /// the document: proxies are a session-local compiler input only.
    public func proxy(asset: MediaAsset, maxDimension: Int = 1280,
                      progress: (@MainActor @Sendable (Double) -> Void)? = nil) async throws -> URL {
        guard (32...4096).contains(maxDimension) else { throw MediaError.unsupported("Proxy dimensions") }
        let source = asset.preparedURL ?? asset.url
        guard source.isFileURL else { throw HelperError.localFilesOnly }
        let probe = try await nativeProbe(source)
        guard probe.hasVideo else { throw MediaError.unsupported("Video proxy needs a video stream") }
        let info = try source.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let key = "proxy-v1|\(source.standardizedFileURL.path)|\(info.fileSize ?? 0)|\(info.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(maxDimension)"
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = CacheStorage.directories[0]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cached = directory.appendingPathComponent(hash + ".mp4")
        if FileManager.default.fileExists(atPath: cached.path) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: cached.path)
            progress?(1); return cached
        }
        let scale = min(1, Double(maxDimension) / Double(max(probe.width, probe.height)))
        let width = max(2, Int(Double(probe.width) * scale) / 2 * 2)
        let height = max(2, Int(Double(probe.height) * scale) / 2 * 2)
        let familiar: [FrameRate] = [.init(numerator: 24000, denominator: 1001), .init(numerator: 30000, denominator: 1001), .init(numerator: 60000, denominator: 1001)]
        let nominal = probe.frameRate.isFinite && probe.frameRate > 0 && probe.frameRate <= 1000 ? probe.frameRate : 30
        let rate = familiar.first { abs(Double($0.numerator) / Double($0.denominator) - nominal) < 0.001 }
            ?? FrameRate(numerator: Int64(nominal * 1000), denominator: 1000)
        var reference = asset
        reference.duration = probe.asset.duration
        let clip = Clip(assetID: reference.id, duration: reference.duration)
        let document = ProjectDocument(sequence: .init(settings: .init(width: width, height: height, frameRate: rate), tracks: [
            .init(name: "Proxy", kind: .video, clips: [clip])
        ]), assets: [reference])
        let temporary = directory.appendingPathComponent(".proxy-building-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await export(.init(document: document), to: temporary, progress: progress)
        try Task.checkCancellation()
        do { try FileManager.default.moveItem(at: temporary, to: cached) }
        catch { if !FileManager.default.fileExists(atPath: cached.path) { throw error } }
        _ = try CacheStorage().cleanup(protectedURLs: [cached, source])
        return cached
    }

    /// Retain active angle-preview caches until the player item is released.
    public func keepCacheFiles(_ urls: Set<URL>, on item: AVPlayerItem) {
        retainCacheLease(CacheLease(urls), on: item)
    }

    /// Session-local audition only; document snapshots and export remain unchanged.
    public func audition(angleID: UUID?, on item: AVPlayerItem) {
        (item.customVideoCompositor as? LifeVideoCompositor)?.setAudition(angleID)
    }

    /// Session-local audio override. Nil restores stored decisions; exports never use this override.
    public func auditionAudio(assetID:UUID?,on item:AVPlayerItem) {
        guard let plan=audioPlans.object(forKey:item) else {return}
        item.audioMix=Self.audioMix(routes:plan.routes,override:assetID)
    }

    private struct AudioRoute {
        let trackID:CMPersistentTrackID; let assetID:UUID; let clip:Clip; let envelope:AutomationEnvelope; let group:MulticamGroup?; let candidate:Bool
    }
    private final class AudioRoutingPlan:NSObject {
        let routes:[AudioRoute]
        init(routes:[AudioRoute]) {self.routes=routes}
    }
    private static func audioMix(routes:[AudioRoute],override:UUID? = nil)->AVMutableAudioMix {
        let mix=AVMutableAudioMix()
        mix.inputParameters=routes.map {route in
            let input=AVMutableAudioMixInputParameters();input.trackID=route.trackID
            input.audioTimePitchAlgorithm=route.clip.preservesPitch ? .spectral:.varispeed
            let enabled:Bool
            if route.group == nil {enabled=true}
            else if let override {enabled=route.candidate && route.assetID==override}
            else {enabled = !route.candidate}
            if enabled {applyEnvelope(route.envelope,to:input,start:route.clip.start,duration:route.clip.duration)}
            else {input.setVolume(0,at:.zero)}
            return input
        }
        return mix
    }

    /// Export uses the exact same composition, compositor, and envelopes as playback.
    /// A sibling temporary file protects an existing destination on failure/cancellation.
    public func export(_ snapshot: ProjectSnapshot, to destination: URL, options: ExportOptions = .init(),
                       progress: (@MainActor @Sendable (Double) -> Void)? = nil) async throws {
        let canonicalDestination = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard !snapshot.document.assets.contains(where: { $0.url.standardizedFileURL.resolvingSymlinksInPath() == canonicalDestination || $0.preparedURL?.standardizedFileURL.resolvingSymlinksInPath() == canonicalDestination }) else {
            throw MediaError.protectsOriginal
        }
        var document = snapshot.document
        if let width = options.width { document.sequence.settings.width = width }
        if let height = options.height { document.sequence.settings.height = height }
        if let frameRate = options.frameRate { document.sequence.settings.frameRate = frameRate }
        let compiled = try await compile(.init(document: document))
        let lease = CacheLease(compiled.cacheURLs)
        defer { withExtendedLifetime(lease) {} }
        _ = try? CacheStorage().cleanup(protectedURLs: Set(document.assets.flatMap { [$0.url, $0.preparedURL].compactMap { $0 } }))
        let plan = ExportRenderPlan(composition: compiled.composition, video: compiled.video, audio: compiled.audio)
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".life-export-\(UUID().uuidString).\(options.format.fileExtension)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        if let progress { progress(0) }
        let job = Task.detached(priority: .userInitiated) { try await ReaderWriterExport.run(plan, to: temporary, options: options, progress: progress) }
        try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else { try FileManager.default.moveItem(at: temporary, to: destination) }
        if let progress { progress(1) }
    }

    private struct Compilation {
        let composition: AVMutableComposition
        let video: AVMutableVideoComposition
        let audio: AVMutableAudioMix
        let cacheURLs: Set<URL>
        let cacheLease: CacheLease
        let audioRoutes:[AudioRoute]
    }

    private func compile(_ snapshot: ProjectSnapshot, proxies: [UUID: URL] = [:],allowAudition:Bool = false) async throws -> Compilation {
        let document = snapshot.document
        try document.validate()
        try AdjustmentLayers.validate(in:document)
        let composition = AVMutableComposition()
        let settings = document.sequence.settings
        let transitions = (document.sequence.transitions ?? []).compactMap { TransitionResolver.resolve($0, in: document) }
        let size = CGSize(width: settings.width, height: settings.height)
        var layers: [RenderLayer] = []
        var audioRoutes:[AudioRoute] = []
        var cacheURLs = Set(proxies.values)
        var leases = [CacheLease(cacheURLs)]
        defer { withExtendedLifetime(leases) {} }
        var end = CMTime.zero
        for track in document.sequence.tracks {
            for clip in track.clips {
                try Task.checkCancellation()
                guard clip.duration.seconds > 0 else { continue }
                let renderStart = transitions.first { $0.transition.rightClipID == clip.id }?.start ?? clip.start
                let renderEnd = transitions.first { $0.transition.leftClipID == clip.id }?.end ?? clip.end
                let clipEnd = CMTimeAdd(clip.start.cmTime, clip.duration.cmTime)
                end = CMTimeMaximum(end, clipEnd)
                if track.kind == .adjustment {
                    try AdjustmentLayers.validate(clip)
                    if !track.isHidden{layers.append(RenderLayer(trackID:nil,clip:clip,transform:.identity,titleImage:nil,renderStart:clip.start,renderEnd:clip.end,isAdjustment:true))}
                    continue
                }
                if let title = clip.title, !track.isHidden {
                    layers.append(RenderLayer(trackID: nil, clip: clip, transform: .identity,
                                              titleImage: TitleRenderer.image(title, size: size), renderStart: renderStart, renderEnd: renderEnd))
                    continue
                }
                if let graphic = clip.graphic, !track.isHidden {
                    guard let image = GraphicRenderer.image(graphic, size: size) else { throw MediaError.unsupported(clip.name) }
                    layers.append(RenderLayer(trackID: nil, clip: clip, transform: .identity, titleImage: image, renderStart: renderStart, renderEnd: renderEnd))
                    continue
                }
                guard let assetID = clip.assetID else { continue }
                guard let reference = document.assets.first(where: { $0.id == assetID }),
                      FileManager.default.fileExists(atPath: (reference.preparedURL ?? reference.url).path) else { throw MediaError.missingAsset(assetID) }
                if let frozen=clip.freezeFrame {
                    if !track.isHidden {
                        let image=try await frozenFrameImage(asset:reference,time:frozen.sourceTime,size:size)
                        layers.append(RenderLayer(trackID:nil,clip:clip,transform:.identity,titleImage:image,renderStart:renderStart,renderEnd:renderEnd))
                    }
                    continue
                }
                if reference.kind == .image {
                    guard let image = StillImage.original(reference.preparedURL ?? reference.url) else { throw MediaError.unsupported(reference.url.lastPathComponent) }
                    if !track.isHidden {
                        let extent = image.extent
                        let scale = min(size.width / extent.width, size.height / extent.height)
                        let fitted = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
                            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                            .transformed(by: CGAffineTransform(translationX: (size.width - extent.width * scale) / 2,
                                                               y: (size.height - extent.height * scale) / 2))
                        layers.append(RenderLayer(trackID: nil, clip: clip, transform: .identity, titleImage: fitted, renderStart: renderStart, renderEnd: renderEnd))
                    }
                    continue
                }
                let group = document.sequence.multicamGroups.first { $0.angleAssetIDs.contains(assetID) || $0.masterAudioAssetID == assetID || ($0.audioAssetIDs?.contains(assetID) ?? false) }
                let asset = AVURLAsset(url: reference.preparedURL ?? reference.url)
                let videoAsset = AVURLAsset(url: proxies[reference.id] ?? reference.preparedURL ?? reference.url)
                let sourceTime = try clip.duration.checkedScaled(by: Int64((clip.speed * 1_000_000).rounded()), over: 1_000_000)
                guard sourceTime.timescale <= Int64(Int32.max), clip.start.timescale <= Int64(Int32.max),
                      clip.duration.timescale <= Int64(Int32.max), clip.sourceStart.timescale <= Int64(Int32.max) else {
                    throw MediaError.invalidRange(reference.url.lastPathComponent)
                }
                let sourceDuration = sourceTime.cmTime
                let sourceRange = CMTimeRange(start: clip.sourceStart.cmTime, duration: sourceDuration)
                let available = try await asset.load(.duration)
                guard CMTimeCompare(CMTimeRangeGetEnd(sourceRange), available) <= 0 else {
                    throw MediaError.invalidRange(reference.url.lastPathComponent)
                }
                if !track.isHidden, track.kind != .audio,
                   let source = try await videoAsset.loadTracks(withMediaType: .video).first,
                   let target = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    let speed = Int64((clip.speed * 1_000_000).rounded())
                    let preHandle = try (clip.start - renderStart).checkedScaled(by: speed, over: 1_000_000)
                    let videoStart = try clip.sourceStart.checkedSubtracting(preHandle)
                    let videoDuration = try (renderEnd - renderStart).checkedScaled(by: speed, over: 1_000_000)
                    guard videoStart.timescale <= Int64(Int32.max), videoDuration.timescale <= Int64(Int32.max),
                          videoStart >= .zero, videoStart + videoDuration <= RationalTime(value: available.value, timescale: Int64(available.timescale)) else { throw MediaError.invalidRange(reference.url.lastPathComponent) }
                    try target.insertTimeRange(CMTimeRange(start: videoStart.cmTime, duration: videoDuration.cmTime), of: source, at: renderStart.cmTime)
                    target.scaleTimeRange(CMTimeRange(start: renderStart.cmTime, duration: videoDuration.cmTime), toDuration: (renderEnd - renderStart).cmTime)
                    let transform = try await source.load(.preferredTransform)
                    layers.append(RenderLayer(trackID: target.trackID, clip: clip, transform: transform, titleImage: nil, multicam: group, renderStart: renderStart, renderEnd: renderEnd))
                }
                if !track.isMuted, (clip.audioEnabled ?? true),
                   let source = try await asset.loadTracks(withMediaType: .audio).first,
                   let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    var envelope = clip.volume
                    var audioSource = source
                    var audioSourceAsset = asset
                    defer { withExtendedLifetime(audioSourceAsset) {} }
                    var audioSourceStart = clip.sourceStart
                    var renderedAudio = false
                    if AudioProcessing.needsProcessing(clip) {
                        let rendered = try await AudioProcessing.prepare(asset: asset, clip: clip)
                        envelope = rendered.envelope
                        cacheURLs.insert(rendered.url); leases.append(CacheLease([rendered.url]))
                        let intermediate = AVURLAsset(url: rendered.url)
                        guard let renderedTrack = try await intermediate.loadTracks(withMediaType: .audio).first else { throw MediaError.exportUnavailable }
                        audioSourceAsset = intermediate; audioSource = renderedTrack; audioSourceStart = .zero; renderedAudio = true
                    } else if clip.speed != 1 {
                        let rendered = try await AudioRetime.render(asset: asset, clip: clip)
                        cacheURLs.insert(rendered); leases.append(CacheLease([rendered]))
                        let intermediate = AVURLAsset(url: rendered)
                        guard let renderedTrack = try await intermediate.loadTracks(withMediaType: .audio).first else { throw MediaError.exportUnavailable }
                        audioSourceAsset = intermediate; audioSource = renderedTrack; audioSourceStart = .zero; renderedAudio = true
                    }
                    let boundaries=Array(Set([clip.start,clip.end]+(group?.audioCuts ?? []).map(\.time).filter{$0>clip.start && $0<clip.end})).sorted()
                    for (left,right) in zip(boundaries,boundaries.dropFirst()) where group.map({MulticamSwitching.selectedAudio(in:$0,at:left)==assetID}) ?? true {
                        let offset=left-clip.start
                        let mappedOffset=renderedAudio ? offset : try offset.checkedScaled(by:Int64((clip.speed*1_000_000).rounded()),over:1_000_000)
                        let mappedDuration=renderedAudio ? right-left : try (right-left).checkedScaled(by:Int64((clip.speed*1_000_000).rounded()),over:1_000_000)
                        try target.insertTimeRange(CMTimeRange(start:(audioSourceStart+mappedOffset).cmTime,duration:mappedDuration.cmTime),of:audioSource,at:left.cmTime)
                    }
                    audioRoutes.append(.init(trackID:target.trackID,assetID:assetID,clip:clip,envelope:envelope,group:group,candidate:false))
                    if allowAudition,group != nil,let auditionTrack=composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid) {
                        let audioDuration=renderedAudio ? clip.duration.cmTime:sourceDuration
                        try auditionTrack.insertTimeRange(CMTimeRange(start:audioSourceStart.cmTime,duration:audioDuration),of:audioSource,at:clip.start.cmTime)
                        audioRoutes.append(.init(trackID:auditionTrack.trackID,assetID:assetID,clip:clip,envelope:envelope,group:group,candidate:true))
                    }
                }
            }
        }
        guard end.seconds > 0 else { throw MediaError.emptySequence }
        // A source canvas also drives the compositor for titles, stills, and gaps.
        // One immutable one-second source is stretched; it never enters the project.
        let canvasURL = try await canvasSource()
        cacheURLs.insert(canvasURL); leases.append(CacheLease([canvasURL]))
        let canvasAsset = AVURLAsset(url: canvasURL)
        if let source = try await canvasAsset.loadTracks(withMediaType: .video).first,
           let target = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try target.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1)), of: source, at: .zero)
            target.scaleTimeRange(CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1)), toDuration: end)
            layers.insert(RenderLayer(trackID: target.trackID,
                clip: Clip(duration: .init(value: end.value, timescale: Int64(end.timescale)), opacity: .init(baseValue: 0)),
                transform: .identity, titleImage: nil), at: 0)
        }
        if composition.duration < end { composition.insertEmptyTimeRange(CMTimeRange(start: composition.duration, duration: CMTimeSubtract(end, composition.duration))) }
        let video = AVMutableVideoComposition()
        video.customVideoCompositorClass = LifeVideoCompositor.self
        video.renderSize = size
        video.frameDuration = CMTime(value: settings.frameRate.denominator, timescale: CMTimeScale(clamping: settings.frameRate.numerator))
        video.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        video.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        video.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        video.instructions = [RenderInstruction(timeRange: CMTimeRange(start: .zero, duration: end), layers: layers, transitions: transitions)]
        let audio = Self.audioMix(routes:audioRoutes)
        return Compilation(composition: composition, video: video, audio: audio, cacheURLs: cacheURLs, cacheLease: CacheLease(cacheURLs),audioRoutes:audioRoutes)
    }

    /// Checks the actual prepared/native stream, rather than inferring audio from a video asset kind.
    public func audioAvailable(asset:MediaAsset) async throws -> Bool {
        try Task.checkCancellation()
        return try await !AVURLAsset(url:asset.preparedURL ?? asset.url).loadTracks(withMediaType:.audio).isEmpty
    }

    private func canvasSource() async throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("org.lifeeditor.canvas", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("black-v1.mov")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let temporary = directory.appendingPathComponent("\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let writer = try AVAssetWriter(outputURL: temporary, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 16, AVVideoHeightKey: 16])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 16, kCVPixelBufferHeightKey as String: 16])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? MediaError.exportUnavailable }
        writer.startSession(atSourceTime: .zero)
        let context = CIContext()
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData { try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(1)) }
            var pixel: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool,
                  CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixel) == kCVReturnSuccess, let pixel else {
                writer.cancelWriting(); throw MediaError.exportUnavailable
            }
            context.render(CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16)), to: pixel)
            guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
                throw writer.error ?? MediaError.exportUnavailable
            }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? MediaError.exportUnavailable }
        // Another concurrently compiled snapshot may have created the same canvas.
        if !FileManager.default.fileExists(atPath: url.path) { try FileManager.default.moveItem(at: temporary, to: url) }
        return url
    }

    static func applyEnvelope(_ envelope: AutomationEnvelope, to input: AVMutableAudioMixInputParameters,
                                      start: RationalTime, duration: RationalTime) {
        let boundaries = Array(Set([RationalTime.zero, duration] + envelope.points.map { $0.time - envelope.evaluationOffset }.filter { $0 > .zero && $0 < duration })).sorted()
        for (left, right) in zip(boundaries, boundaries.dropFirst()) {
            let interpolation = envelope.points.sorted { $0.time < $1.time }.last { $0.time <= left + envelope.evaluationOffset }?.interpolation ?? .linear
            if interpolation == .hold {
                input.setVolume(Float(envelope.value(at: left)), at: (start + left).cmTime)
                input.setVolume(Float(envelope.value(at: right)), at: (start + right).cmTime)
                continue
            }
            let segments = interpolation == .eased ? 32 : 1
            for step in 0..<segments {
                let t0 = left + (right-left).scaled(by: Int64(step), over: Int64(segments))
                let t1 = left + (right-left).scaled(by: Int64(step+1), over: Int64(segments))
                input.setVolumeRamp(fromStartVolume: Float(envelope.value(at: t0)),
                                    toEndVolume: Float(envelope.value(at: t1)),
                                    timeRange: CMTimeRange(start: (start+t0).cmTime, duration: (t1-t0).cmTime))
            }
        }
    }


}
