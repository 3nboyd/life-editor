import Foundation
@preconcurrency import AVFoundation
import CoreImage
import CoreVideo
import LifeCore

struct RenderLayer: @unchecked Sendable {
    let trackID: CMPersistentTrackID?
    let clip: Clip
    let transform: CGAffineTransform
    let titleImage: CIImage?
    var multicam: MulticamGroup? = nil
    var renderStart: RationalTime? = nil
    var renderEnd: RationalTime? = nil
    var isAdjustment=false
    func isActive(at time: RationalTime) -> Bool { (renderStart ?? clip.start) <= time && time < (renderEnd ?? clip.end) }
}

final class RenderInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    let layers: [RenderLayer]
    let transitions: [ResolvedTransition]
    init(timeRange: CMTimeRange, layers: [RenderLayer], transitions: [ResolvedTransition] = []) {
        self.timeRange = timeRange; self.layers = layers; self.transitions = transitions
        self.requiredSourceTrackIDs = layers.compactMap(\.trackID).map { NSNumber(value: $0) }
    }
}

/// One deterministic renderer for AVFoundation playback and file export.
/// Core Image performs composition in an explicit linear Rec.709 working space.
final class LifeVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.lifeeditor.compositor", qos: .userInitiated)
    private let cancellationLock = NSLock()
    private var generation: UInt64 = 0
    private var auditionAngleID: UUID?
    func setAudition(_ id: UUID?) {
        cancellationLock.withLock { auditionAngleID = id }
    }
    func selectedAngle(in group: MulticamGroup, at time: RationalTime) -> UUID? {
        if let audition = cancellationLock.withLock({ auditionAngleID }), group.angleAssetIDs.contains(audition) { return audition }
        return group.cuts.sorted { $0.time < $1.time }.last { $0.time <= time }?.angleID ?? group.angleAssetIDs.first
    }
    private let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.itur_709)!,
        .cacheIntermediates: false
    ])
    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]]
    }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true]
    }
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        let submitted = cancellationLock.withLock { generation }
        queue.async { [self] in
            guard cancellationLock.withLock({ generation == submitted }) else {
                request.finishCancelledRequest(); return
            }
            render(request)
        }
    }
    func cancelAllPendingVideoCompositionRequests() {
        cancellationLock.withLock { generation &+= 1 }
    }
    private func layerImage(_ layer: RenderLayer, request: AVAsynchronousVideoCompositionRequest, canvas: CGRect, time: RationalTime) -> CIImage? {
        if let group = layer.multicam, selectedAngle(in: group, at: time) != layer.clip.assetID { return nil }
        var foreground: CIImage
        if let title = layer.titleImage { foreground = title }
        else if let id = layer.trackID, let buffer = request.sourceFrame(byTrackID: id) {
            foreground = CIImage(cvPixelBuffer: buffer).transformed(by: layer.transform)
            let extent = foreground.extent
            let scale = min(canvas.width / extent.width, canvas.height / extent.height)
            foreground = foreground.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: (canvas.width - extent.width * scale) / 2,
                                                   y: (canvas.height - extent.height * scale) / 2))
        } else { return nil }
        if let title = layer.clip.title { foreground = TitleRenderer.animated(foreground, title: title, localTime: time - layer.clip.start, canvas: canvas) }
        let localTime = max(.zero, min(layer.clip.duration, time - layer.clip.start))
        foreground = EffectRenderer.apply(layer.clip.effects ?? [], to: foreground, time: time - layer.clip.start + (layer.clip.freezeFrame?.effectTimeOffset ?? .zero), sourceTime:layer.clip.sourceTime(at:time))
        foreground = EffectRenderer.transform(foreground, visual: layer.clip.visual, canvas: canvas)
        let opacity = max(0, min(1, layer.clip.opacity.value(at: localTime)))
        return foreground.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)])
    }

    private func render(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? RenderInstruction,
              let output = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "LifeEditor.Render", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot allocate a preview frame."]))
            return
        }
        let canvas = CGRect(origin: .zero, size: request.renderContext.size)
        var image = CIImage(color: .black).cropped(to: canvas)
        let time = RationalTime(value: request.compositionTime.value, timescale: Int64(request.compositionTime.timescale))
        // Pair transitions render once at their track's layer position. Incoming
        // clips never cover the pair a second time, including unsorted clip arrays.
        let activeTransitions = instruction.transitions.filter { $0.start <= time && time < $0.end }
        for layer in instruction.layers where layer.isActive(at: time) {
            if layer.isAdjustment {
                let adjusted=EffectRenderer.apply(layer.clip.effects ?? [],to:image,time:layer.clip.sourceTime(at:time)).cropped(to:canvas)
                let opacity=max(0,min(1,layer.clip.opacity.value(at:time-layer.clip.start)))
                image=image.applyingFilter("CIDissolveTransition",parameters:["inputTargetImage":adjusted,"inputTime":opacity]).cropped(to:canvas)
                continue
            }
            if activeTransitions.contains(where: { $0.transition.rightClipID == layer.clip.id }) { continue }
            let foreground: CIImage
            if let pair = activeTransitions.first(where: { $0.transition.leftClipID == layer.clip.id }),
               let right = instruction.layers.first(where: { $0.clip.id == pair.transition.rightClipID }) {
                let leftImage = layerImage(layer, request: request, canvas: canvas, time: time) ?? CIImage.empty()
                let rightImage = layerImage(right, request: request, canvas: canvas, time: time) ?? CIImage.empty()
                foreground = TransitionRenderer.image(from: leftImage, to: rightImage, transition: pair.transition,
                    progress: (time - pair.start).seconds / (pair.end - pair.start).seconds, canvas: canvas)
            } else {
                guard let rendered = layerImage(layer, request: request, canvas: canvas, time: time) else { continue }
                foreground = rendered
            }
            image = foreground.composited(over: image).cropped(to: canvas)
        }
        context.render(image, to: output, bounds: canvas, colorSpace: CGColorSpace(name: CGColorSpace.itur_709))
        request.finish(withComposedVideoFrame: output)
    }
}
