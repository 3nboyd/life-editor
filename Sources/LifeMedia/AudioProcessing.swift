import Foundation
@preconcurrency import AVFoundation
import CryptoKit
import LifeCore

struct PreparedAudio {
    let url: URL
    let envelope: AutomationEnvelope
}

enum AudioProcessing {
    static func headroom(_ envelope: AutomationEnvelope) -> Double {
        max(1, envelope.baseValue * (envelope.points.map(\.value).max() ?? 1))
    }
    static func needsProcessing(_ clip: Clip) -> Bool {
        (clip.audio ?? AudioSettings()) != AudioSettings() || headroom(clip.volume) > 1
    }
    static func prepare(asset: AVAsset, clip: Clip) async throws -> PreparedAudio {
        let settings = clip.audio ?? AudioSettings()
        let room = headroom(clip.volume)
        var envelope = clip.volume
        envelope.baseValue /= room
        if settings.limiterEnabled { envelope = .init() }
        let directory = CacheStorage.directories[3]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = (asset as? AVURLAsset)?.url
        let metadata = try original?.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var identity = Data("audio-v1|\(original?.path ?? "")|\(metadata?.fileSize ?? 0)|\(metadata?.contentModificationDate?.timeIntervalSince1970 ?? 0)".utf8)
        identity.append(try encoder.encode(clip))
        let hash = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        let cached = directory.appendingPathComponent(hash + ".wav")
        if FileManager.default.fileExists(atPath: cached.path) { return .init(url: cached, envelope: envelope) }
        let temporary = directory.appendingPathComponent(".audio-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let source: AVAsset
        let start: CMTime
        var lease: CacheLease?
        defer { withExtendedLifetime(lease) {} }
        if clip.speed != 1 {
            let retimed = try await AudioRetime.render(asset: asset, clip: clip)
            lease = CacheLease([retimed]); source = AVURLAsset(url: retimed); start = .zero
        } else { source = asset; start = clip.sourceStart.cmTime }
        let reader = try AVAssetReader(asset: source)
        let tracks = try await source.loadTracks(withMediaType: .audio)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false])
        output.alwaysCopiesSampleData = false
        reader.timeRange = CMTimeRange(start: start, duration: clip.duration.cmTime)
        reader.add(output)
        let io = BlockingAssetReader(reader: reader, output: output, label: "life.audio-processing.reader")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        var file: AVAudioFile? = try AVAudioFile(forWriting: temporary, settings: format.settings.merging([AVLinearPCMIsNonInterleaved: false]) { _, new in new })
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var buffered = 0
        func write(_ frame: StereoSample) throws {
            buffer.floatChannelData![0][buffered] = Float(frame.left)
            buffer.floatChannelData![1][buffered] = Float(frame.right)
            buffered += 1
            if buffered == 4096 { buffer.frameLength = 4096; try file!.write(from: buffer); buffered = 0 }
        }
        let wanted = Int64((clip.duration.seconds * 48000).rounded())
        var index: Int64 = 0
        var dsp = ClipDSP(settings: settings, headroom: room)
        var limiter = LookaheadLimiter(ceiling: pow(10, settings.limiterCeilingDB / 20))
        var sampler = EnvelopeSampler(clip.volume)
        func process(_ left: Double, _ right: Double) throws {
            guard left.isFinite, right.isFinite else { throw MediaError.unsupported("Non-finite audio samples") }
            var sample = dsp.process(left, right)
            if settings.limiterEnabled {
                let volume = sampler.value(at: Double(index) / 48000) / room
                sample.left *= volume; sample.right *= volume
                if let limited = limiter.push(sample) { try write(limited) }
            } else { try write(sample) }
            index += 1
        }
        do {
            return try await withTaskCancellationHandler {
                try await io.start()
                while index < wanted, let sample = try await io.next().buffer, let block = CMSampleBufferGetDataBuffer(sample) {
                    try Task.checkCancellation()
                    let frames = CMSampleBufferGetNumSamples(sample)
                    var samples = [Float](repeating: 0, count: frames * 2)
                    let status = samples.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: frames * 8, destination: $0.baseAddress!) }
                    guard status == kCMBlockBufferNoErr else { throw MediaError.exportUnavailable }
                    for frame in 0..<min(frames, Int(wanted - index)) { try process(Double(samples[frame * 2]), Double(samples[frame * 2 + 1])) }
                }
                if reader.status == .failed { throw reader.error ?? MediaError.exportUnavailable }
                // The requested frame count can end before the reader reaches EOF.
                // Stop it off the cooperative executor before releasing its source lease.
                await io.cancelAndWait()
                try Task.checkCancellation()
                while index < wanted { try Task.checkCancellation(); try process(0, 0) }
                if settings.limiterEnabled {
                    for _ in 0..<LookaheadLimiter.lookahead { if let sample = limiter.push(.zero) { try write(sample) } }
                }
                if buffered > 0 { buffer.frameLength = AVAudioFrameCount(buffered); try file!.write(from: buffer) }
                file = nil
                if FileManager.default.fileExists(atPath: cached.path) { try? FileManager.default.removeItem(at: temporary) }
                else { try FileManager.default.moveItem(at: temporary, to: cached) }
                return .init(url: cached, envelope: envelope)
            } onCancel: { io.cancel() }
        } catch { await io.cancelAndWait(); throw error }
    }
}

struct StereoSample {
    var left: Double; var right: Double
    static let zero = Self(left: 0, right: 0)
}

/// Three original fixed-frequency RBJ cookbook bands: 120Hz low shelf,
/// 1kHz/Q0.8 bell, 8kHz high shelf. State is independent for each stereo channel.
struct Biquad {
    var b0: Double = 1, b1: Double = 0, b2: Double = 0, a1: Double = 0, a2: Double = 0
    private var z1: Double = 0, z2: Double = 0
    init(b0: Double = 1, b1: Double = 0, b2: Double = 0, a1: Double = 0, a2: Double = 0) { self.b0=b0; self.b1=b1; self.b2=b2; self.a1=a1; self.a2=a2 }
    mutating func sample(_ x: Double) -> Double {
        let y = b0 * x + z1; z1 = b1 * x - a1 * y + z2; z2 = b2 * x - a2 * y; return y
    }
    static func band(frequency: Double, gain: Double, kind: Int) -> Self {
        if gain == 0 { return Self() }
        let a = pow(10, gain / 40), w = 2 * Double.pi * frequency / 48000
        let c = cos(w), s = sin(w), alpha = s / 2 * sqrt(2), beta = 2 * sqrt(a) * alpha
        let b0, b1, b2, a0, a1, a2: Double
        if kind == 0 {
            b0=a*((a+1)-(a-1)*c+beta); b1=2*a*((a-1)-(a+1)*c); b2=a*((a+1)-(a-1)*c-beta)
            a0=(a+1)+(a-1)*c+beta; a1 = -2*((a-1)+(a+1)*c); a2=(a+1)+(a-1)*c-beta
        } else if kind == 2 {
            b0=a*((a+1)+(a-1)*c+beta); b1 = -2*a*((a-1)+(a+1)*c); b2=a*((a+1)+(a-1)*c-beta)
            a0=(a+1)-(a-1)*c+beta; a1=2*((a-1)-(a+1)*c); a2=(a+1)-(a-1)*c-beta
        } else {
            let qAlpha = s / 1.6
            b0=1+qAlpha*a; b1 = -2*c; b2=1-qAlpha*a; a0=1+qAlpha/a; a1 = -2*c; a2=1-qAlpha/a
        }
        return .init(b0:b0/a0,b1:b1/a0,b2:b2/a0,a1:a1/a0,a2:a2/a0)
    }
}
private struct ClipDSP {
    let settings: AudioSettings
    let gain: Double
    var left: [Biquad], right: [Biquad]
    init(settings: AudioSettings, headroom: Double) {
        self.settings = settings; gain = pow(10, settings.gainDB / 20) * headroom
        left = [.band(frequency: 120, gain: settings.eqLowDB, kind: 0), .band(frequency: 1000, gain: settings.eqMidDB, kind: 1), .band(frequency: 8000, gain: settings.eqHighDB, kind: 2)]
        right = left
    }
    mutating func process(_ originalLeft: Double, _ originalRight: Double) -> StereoSample {
        var l = originalLeft, r = originalRight
        switch settings.channels { case .left: r = l; case .right: l = r; case .mono: l = (l + r) / 2; r = l; case .stereo: break }
        for index in left.indices { l = left[index].sample(l); r = right[index].sample(r) }
        l *= gain * (settings.pan > 0 ? cos(settings.pan * .pi / 2) : 1)
        r *= gain * (settings.pan < 0 ? cos(settings.pan * .pi / 2) : 1)
        return .init(left: l, right: r)
    }
}
private struct EnvelopeSampler {
    let base: Double
    let points: [(Double, Double, Interpolation)]
    var cursor = 0
    init(_ envelope: AutomationEnvelope) {
        base = envelope.baseValue
        points = envelope.points.sorted { $0.time < $1.time }.map { ($0.time.seconds - envelope.evaluationOffset.seconds, $0.value, $0.interpolation) }
    }
    mutating func value(at time: Double) -> Double {
        guard let first = points.first else { return base }
        if time < first.0 { return base * first.1 }
        while cursor + 1 < points.count && points[cursor + 1].0 <= time { cursor += 1 }
        let left = points[cursor]
        guard cursor + 1 < points.count else { return base * left.1 }
        let right = points[cursor + 1]
        if left.2 == .hold { return base * left.1 }
        var t = max(0, min(1, (time - left.0) / (right.0 - left.0)))
        if left.2 == .eased { t = t*t*(3-2*t) }
        return base * (left.1 + (right.1-left.1)*t)
    }
}
private struct LookaheadLimiter {
    static let lookahead = 240
    let ceiling: Double
    var ring = [StereoSample](repeating: .zero, count: lookahead + 1)
    var peaks: [(Int64, Double)] = []
    var head = 0
    var input: Int64 = 0
    var gain = 1.0
    mutating func push(_ sample: StereoSample) -> StereoSample? {
        ring[Int(input % Int64(ring.count))] = sample
        let peak = max(abs(sample.left), abs(sample.right))
        while peaks.count > head && peaks.last!.1 <= peak { peaks.removeLast() }
        peaks.append((input, peak))
        let output = input - Int64(Self.lookahead); input += 1
        guard output >= 0 else { return nil }
        while head < peaks.count && peaks[head].0 < output { head += 1 }
        let maximum = peaks[head].1
        let target = maximum > ceiling ? ceiling / maximum : 1
        if target < gain { gain = target } else { gain += (target - gain) * (1 - exp(-1 / (48000 * 0.05))) }
        if head > 4096 { peaks.removeFirst(head); head = 0 }
        let frame = ring[Int(output % Int64(ring.count))]
        return .init(left: max(-ceiling, min(ceiling, frame.left * gain)), right: max(-ceiling, min(ceiling, frame.right * gain)))
    }
}
