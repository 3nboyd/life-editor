import Foundation
@preconcurrency import AVFoundation
import LifeCore

public struct AudioMeterFrame: Equatable, Sendable {
    public let time: RationalTime
    public let leftDBFS: Double
    public let rightDBFS: Double
    public init(time: RationalTime, leftDBFS: Double, rightDBFS: Double) { self.time=time; self.leftDBFS=leftDBFS; self.rightDBFS=rightDBFS }
}
struct AudioScanResult: Sendable {
    let measurement: AudioMeasurement
    let meters: [AudioMeterFrame]
}
actor AudioMeasurementCache {
    static let shared = AudioMeasurementCache()
    private var results: [String: AudioScanResult] = [:]
    private var order: [String] = []
    func get(_ key: String) -> AudioScanResult? { results[key] }
    func put(_ value: AudioScanResult, key: String) {
        let bytes = value.meters.count * 32
        guard bytes <= 64_000_000 else { return }
        order.removeAll { $0 == key }; order.append(key); results[key] = value
        while order.count > 8 || results.values.reduce(0, { $0 + $1.meters.count * 32 }) > 64_000_000 {
            results.removeValue(forKey: order.removeFirst())
        }
    }
}

enum AudioScan {
    static func run(_ plan: ExportRenderPlan, interval: Double,
                    progress: (@MainActor @Sendable (Double) -> Void)?) async throws -> AudioScanResult {
        let duration = try await plan.composition.load(.duration)
        let wanted = Int64((duration.seconds * 48000).rounded())
        let tracks = try await plan.composition.loadTracks(withMediaType: .audio)
        var scan = AudioAccumulator(bucketSize: max(1, Int(interval * 48000)))
        if tracks.isEmpty {
            while scan.count < wanted { try Task.checkCancellation(); scan.sample(0, 0) }
            if let progress { await progress(1) }
            return scan.finish()
        }
        let reader = try AVAssetReader(asset: plan.composition)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false])
        output.audioMix = plan.audio; output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else{throw MediaError.exportUnavailable};reader.add(output)
        let io=BlockingAssetReader(reader:reader,output:output,label:"org.lifeeditor.measure.read")
        return try await withTaskCancellationHandler{
            do{
                try await io.start()
                var reported = -1.0
                while let buffer = try await io.next().buffer {
                    if CMSampleBufferGetNumSamples(buffer)==0{continue}
                    guard let block=CMSampleBufferGetDataBuffer(buffer) else{throw MediaError.exportUnavailable}
                    try Task.checkCancellation()
                    let frames = CMSampleBufferGetNumSamples(buffer)
                    let position = max(0, Int64((CMSampleBufferGetPresentationTimeStamp(buffer).seconds * 48000).rounded()))
                    while scan.count < min(wanted, position) { if scan.count % 4096 == 0 { try Task.checkCancellation() }; scan.sample(0, 0) }
                    var samples = [Float](repeating: 0, count: frames * 2)
                    let status = samples.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: frames * 8, destination: $0.baseAddress!) }
                    guard status == kCMBlockBufferNoErr else { throw MediaError.exportUnavailable }
                    let skip = min(frames, max(0, Int(scan.count - position)))
                    for index in skip..<frames where scan.count < wanted {
                        let left = Double(samples[index * 2]), right = Double(samples[index * 2 + 1])
                        guard left.isFinite, right.isFinite else { throw MediaError.unsupported("Non-finite audio samples") }
                        scan.sample(left, right)
                    }
                    let value = min(0.99, Double(scan.count) / Double(max(1, wanted)))
                    if value - reported >= 0.01, let progress { await progress(value); reported = value }
                }
                try await io.requireCompleted()
                while scan.count < wanted { try Task.checkCancellation(); scan.sample(0, 0) }
                if let progress { await progress(1) }
                return scan.finish()
            }catch{await io.cancelAndWait();throw error}
        }onCancel:{io.cancel()}
    }
}

/// Stereo BS.1770 K weighting at exactly 48kHz, with 400ms blocks/100ms hops,
/// -70LUFS absolute and -10LU relative gating. This measures integrated sample
/// loudness; sample peaks are not labeled as oversampled true peaks.
struct AudioAccumulator {
    private let bucketSize: Int
    private(set) var count: Int64 = 0
    private var sumSquares = 0.0, peak = 0.0
    private var meterLeft = 0.0, meterRight = 0.0
    private var meters: [AudioMeterFrame] = []
    private var leftShelf = Biquad(b0: 1.53512485958697, b1: -2.69169618940638, b2: 1.19839281085285, a1: -1.69065929318241, a2: 0.73248077421585)
    private var rightShelf = Biquad(b0: 1.53512485958697, b1: -2.69169618940638, b2: 1.19839281085285, a1: -1.69065929318241, a2: 0.73248077421585)
    private var leftRLB = Biquad(b0: 1, b1: -2, b2: 1, a1: -1.99004745483398, a2: 0.99007225036621)
    private var rightRLB = Biquad(b0: 1, b1: -2, b2: 1, a1: -1.99004745483398, a2: 0.99007225036621)
    private var hopEnergy = 0.0
    private var hops: [Double] = []
    private var blockEnergies: [Double] = []
    init(bucketSize: Int) { self.bucketSize = bucketSize }
    mutating func sample(_ left: Double, _ right: Double) {
        sumSquares += left * left + right * right
        peak = max(peak, abs(left), abs(right))
        meterLeft = max(meterLeft, abs(left)); meterRight = max(meterRight, abs(right))
        let l = leftRLB.sample(leftShelf.sample(left)), r = rightRLB.sample(rightShelf.sample(right))
        hopEnergy += l*l + r*r
        count += 1
        if count % 4800 == 0 {
            hops.append(hopEnergy); hopEnergy = 0
            if hops.count > 4 { hops.removeFirst() }
            if hops.count == 4 { blockEnergies.append(hops.reduce(0, +) / 19200) }
        }
        if count % Int64(bucketSize) == 0 { appendMeter(frames: bucketSize) }
    }
    private mutating func appendMeter(frames: Int) {
        meters.append(.init(time: .init(value: count - Int64(frames), timescale: 48000), leftDBFS: Self.db(meterLeft), rightDBFS: Self.db(meterRight)))
        meterLeft = 0; meterRight = 0
    }
    mutating func finish() -> AudioScanResult {
        let remainder = Int(count % Int64(bucketSize))
        if remainder > 0 { appendMeter(frames: remainder) }
        let absolute = blockEnergies.filter { Self.loudness($0) >= -70 }
        let loudness: Double?
        if count < 19200 { loudness = nil }
        else if absolute.isEmpty { loudness = -.infinity }
        else {
            let preliminary = absolute.reduce(0, +) / Double(absolute.count)
            let threshold = Self.loudness(preliminary) - 10
            let gated = absolute.filter { Self.loudness($0) >= threshold }
            loudness = Self.loudness(gated.reduce(0, +) / Double(gated.count))
        }
        return .init(measurement: .init(peakDBFS: Self.db(peak), rmsDBFS: Self.db(sqrt(sumSquares / Double(max(1, count) * 2))),
                                       loudnessLUFS: loudness, sampleCount: count), meters: meters)
    }
    static func db(_ amplitude: Double) -> Double { amplitude > 0 ? 20 * log10(amplitude) : -.infinity }
    static func loudness(_ energy: Double) -> Double { energy > 0 ? -0.691 + 10 * log10(energy) : -.infinity }
}
