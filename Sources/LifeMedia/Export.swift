import Foundation
@preconcurrency import AVFoundation
import LifeCore

public enum ExportFormat: String, CaseIterable, Sendable {
    case h264, hevc, proRes, wav, aiff, m4a
    public var fileExtension: String {
        switch self { case .h264, .hevc: "mp4"; case .proRes: "mov"; case .wav: "wav"; case .aiff: "aiff"; case .m4a: "m4a" }
    }
    public var hasVideo: Bool { self == .h264 || self == .hevc || self == .proRes }
    var fileType: AVFileType {
        switch self { case .h264, .hevc: .mp4; case .proRes: .mov; case .wav: .wav; case .aiff: .aiff; case .m4a: .m4a }
    }
}

public struct ExportOptions: Sendable {
    public var format: ExportFormat
    public var width: Int?
    public var height: Int?
    public var frameRate: FrameRate?
    public var rangeStart: RationalTime?
    public var rangeDuration: RationalTime?
    public init(format: ExportFormat = .h264, width: Int? = nil, height: Int? = nil,
                frameRate: FrameRate? = nil, rangeStart: RationalTime? = nil, rangeDuration: RationalTime? = nil) {
        self.format = format; self.width = width; self.height = height; self.frameRate = frameRate
        self.rangeStart = rangeStart; self.rangeDuration = rangeDuration
    }
}

/// The compiler freezes these graphs before handing exclusive read access to IO workers.
struct ExportRenderPlan: @unchecked Sendable {
    let composition: AVMutableComposition
    let video: AVMutableVideoComposition
    let audio: AVMutableAudioMix
}

/// Reader and writer methods used below support distinct output/input queues.
/// No mutable document or UI state enters this worker.
private final class ExportIO: @unchecked Sendable {
    let reader: AVAssetReader
    let writer: AVAssetWriter
    private let lock=NSLock()
    private var cancelled=false
    private let cancellationQueue=DispatchQueue(label:"org.lifeeditor.export.cancel",qos:.userInitiated)
    init(reader: AVAssetReader, writer: AVAssetWriter) { self.reader = reader; self.writer = writer }
    func checkCancellation()throws{if lock.withLock({cancelled}){throw CancellationError()}}
    func cancelAndWait()async{
        cancel()
        await withCheckedContinuation{(continuation:CheckedContinuation<Void,Never>) in cancellationQueue.async{continuation.resume()}}
    }
    func cancel() {
        lock.withLock{cancelled=true}
        // A second pass after startup/unwind also covers cancellation before
        // native objects entered reading/writing state. Unknown states are untouched.
        cancellationQueue.async{[self] in
            if reader.status == .reading{reader.cancelReading()}
            if writer.status == .writing{writer.cancelWriting()}
        }
    }
}
/// CMSampleBuffer is immutable after the reader hands it to this stream.
private struct ExportSample:@unchecked Sendable{let buffer:CMSampleBuffer?}
private struct ExportStream: @unchecked Sendable {
    let output: AVAssetReaderOutput
    let input: AVAssetWriterInput
}
private final class ExportProgress: @unchecked Sendable {
    let callback: (@MainActor @Sendable (Double) -> Void)?
    let range: CMTimeRange
    private let lock = NSLock()
    private var last: Double = -1
    private var streams: [Int: Double] = [:]
    private let streamCount: Int
    @MainActor private var delivered: Double = -1
    init(range: CMTimeRange, streamCount: Int, callback: (@MainActor @Sendable (Double) -> Void)?) {
        self.range = range; self.streamCount = streamCount; self.callback = callback
    }
    func report(_ time: CMTime, stream: Int) async {
        let fraction = max(0, min(0.99, CMTimeSubtract(time, range.start).seconds / range.duration.seconds))
        let value = lock.withLock { () -> Double? in
            streams[stream] = max(streams[stream] ?? 0, fraction)
            let combined = streams.values.reduce(0, +) / Double(streamCount)
            guard combined - last >= 0.01 else { return nil }
            last = combined; return combined
        }
        if let value { await deliver(value) }
    }
    @MainActor private func deliver(_ value: Double) {
        guard value >= delivered else { return }
        delivered = value; callback?(value)
    }
}

enum ReaderWriterExport {
    static func run(_ plan: ExportRenderPlan, to url: URL, options: ExportOptions,
                    progress: (@MainActor @Sendable (Double) -> Void)?) async throws {
        try await ExportAdmission.shared.acquire()
        do{try await perform(plan,to:url,options:options,progress:progress);await ExportAdmission.shared.release()}
        catch{await ExportAdmission.shared.release();throw error}
    }
    private static func perform(_ plan:ExportRenderPlan,to url:URL,options:ExportOptions,
                                progress:(@MainActor @Sendable (Double)->Void)?)async throws{
        try Task.checkCancellation()
        let duration = try await plan.composition.load(.duration)
        let start = options.rangeStart?.cmTime ?? .zero
        let length = options.rangeDuration?.cmTime ?? CMTimeSubtract(duration, start)
        guard start.isNumeric, length.isNumeric, start >= .zero, length > .zero,
              CMTimeAdd(start, length) <= duration else { throw MediaError.invalidRange("Export range") }
        let range = CMTimeRange(start: start, duration: length)
        let reader = try AVAssetReader(asset: plan.composition)
        reader.timeRange = range
        let writer = try AVAssetWriter(outputURL: url, fileType: options.format.fileType)
        let io = ExportIO(reader: reader, writer: writer)
        let control=BlockingIOWorker(label:"org.lifeeditor.export.control")
        var streams: [ExportStream] = []
        if options.format.hasVideo {
            let tracks = try await plan.composition.loadTracks(withMediaType: .video)
            let output = AVAssetReaderVideoCompositionOutput(videoTracks: tracks, videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey as String: true])
            output.videoComposition = plan.video
            output.alwaysCopiesSampleData = false
            let codec: AVVideoCodecType = options.format == .hevc ? .hevc : options.format == .proRes ? .proRes422 : .h264
            var settings: [String: Any] = [AVVideoCodecKey: codec,
                AVVideoWidthKey: Int(plan.video.renderSize.width), AVVideoHeightKey: Int(plan.video.renderSize.height),
                AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]]
            if options.format != .proRes {
                settings[AVVideoCompressionPropertiesKey] = [AVVideoAverageBitRateKey:
                    max(500_000, Int(plan.video.renderSize.width * plan.video.renderSize.height * (options.format == .hevc ? 4 : 6)))]
            }
            guard writer.canApply(outputSettings: settings, forMediaType: .video) else { throw MediaError.exportUnavailable }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            guard reader.canAdd(output), writer.canAdd(input) else { throw MediaError.exportUnavailable }
            reader.add(output); writer.add(input); streams.append(.init(output: output, input: input))
        }
        let audioTracks = try await plan.composition.loadTracks(withMediaType: .audio)
        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
            output.audioMix = plan.audio
            output.alwaysCopiesSampleData = false
            let pcm = options.format == .wav || options.format == .aiff
            var settings: [String: Any] = [AVFormatIDKey: pcm ? kAudioFormatLinearPCM : kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2]
            if pcm {
                settings[AVLinearPCMBitDepthKey] = 16; settings[AVLinearPCMIsFloatKey] = false
                settings[AVLinearPCMIsBigEndianKey] = options.format == .aiff
                settings[AVLinearPCMIsNonInterleaved] = false
            } else { settings[AVEncoderBitRateKey] = 192000 }
            guard writer.canApply(outputSettings: settings, forMediaType: .audio) else { throw MediaError.exportUnavailable }
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            guard reader.canAdd(output), writer.canAdd(input) else { throw MediaError.exportUnavailable }
            reader.add(output); writer.add(input); streams.append(.init(output: output, input: input))
        } else if !options.format.hasVideo { throw MediaError.unsupported("Audio-only export needs an audible recording") }
        let report = ExportProgress(range: range, streamCount: streams.count, callback: progress)
        try await withTaskCancellationHandler {
            do {
            try await control.run{
                try io.checkCancellation()
                guard io.writer.startWriting() else{throw io.writer.error ?? MediaError.exportUnavailable}
                io.writer.startSession(atSourceTime:start)
                guard io.reader.startReading() else{io.writer.cancelWriting();throw io.reader.error ?? MediaError.exportUnavailable}
            }
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for (streamIndex, stream) in streams.enumerated() {
                        group.addTask {
                            let worker=BlockingIOWorker(label:"org.lifeeditor.export.stream.\(streamIndex)")
                            while true {
                                try Task.checkCancellation()
                                let ready=try await worker.run{try io.checkCancellation();guard io.writer.status == .writing else{throw io.writer.error ?? MediaError.exportUnavailable};return stream.input.isReadyForMoreMediaData}
                                if !ready{try await Task.sleep(for:.milliseconds(2));continue}
                                let sample=try await worker.run{try io.checkCancellation();return ExportSample(buffer:stream.output.copyNextSampleBuffer())}
                                guard let buffer=sample.buffer else{break}
                                try await worker.run{try io.checkCancellation();guard let buffer=sample.buffer,stream.input.append(buffer) else{throw io.writer.error ?? MediaError.exportUnavailable}}
                                await report.report(CMSampleBufferGetPresentationTimeStamp(buffer),stream:streamIndex)
                            }
                            try await worker.run{try io.checkCancellation();stream.input.markAsFinished()}
                        }
                    }
                    do{while let _ = try await group.next(){}}catch{io.cancel();group.cancelAll();throw error}
                }
                try Task.checkCancellation()
                try await control.run{
                    try io.checkCancellation()
                    guard io.reader.status == .completed else{throw io.reader.error ?? MediaError.exportUnavailable}
                    io.writer.endSession(atSourceTime:CMTimeRangeGetEnd(range))
                }
                await writer.finishWriting()
                try Task.checkCancellation()
                guard writer.status == .completed else { throw writer.error ?? MediaError.exportUnavailable }
            } catch { await io.cancelAndWait();throw error }
        } onCancel: { io.cancel() }
    }
}
