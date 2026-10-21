import Foundation
@preconcurrency import AVFoundation
import LifeCore
import CryptoKit

/// Replaceable native intermediates keep AVFoundation's real-time pitch latency
/// out of document timing. Preview and export read the same rendered samples.
enum AudioRetime {
    static func render(asset: AVAsset, clip: Clip) async throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("org.lifeeditor.retime", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let originalURL = (asset as? AVURLAsset)?.url
        let metadata = try originalURL?.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let key = "v2|\(originalURL?.path ?? "")|\(metadata?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(metadata?.fileSize ?? 0)|\(clip.sourceStart)|\(clip.duration)|\(clip.speed)|\(clip.preservesPitch)"
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let cachedURL = directory.appendingPathComponent("\(digest).wav")
        if FileManager.default.fileExists(atPath: cachedURL.path) { return cachedURL }
        let sourceURL = directory.appendingPathComponent("\(UUID()).wav")
        let outputURL = directory.appendingPathComponent("\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        var sourceFile: AVAudioFile? = try AVAudioFile(forWriting: sourceURL, settings: format.settings.merging([AVLinearPCMIsNonInterleaved: false]) { _, new in new })
        let reader = try AVAssetReader(asset: asset)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false])
        reader.timeRange = CMTimeRange(start: clip.sourceStart.cmTime,
            duration: CMTime(seconds: clip.duration.seconds * clip.speed, preferredTimescale: 48000))
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? MediaError.exportUnavailable }
        while let sample = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sample) {
            try Task.checkCancellation()
            let frames = CMSampleBufferGetNumSamples(sample)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { throw MediaError.exportUnavailable }
            buffer.frameLength = AVAudioFrameCount(frames)
            var bytes = [Float](repeating: 0, count: frames * 2)
            _ = bytes.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: frames * 8, destination: $0.baseAddress!) }
            for frame in 0..<frames {
                buffer.floatChannelData![0][frame] = bytes[frame * 2]
                buffer.floatChannelData![1][frame] = bytes[frame * 2 + 1]
            }
            try sourceFile!.write(from: buffer)
        }
        guard reader.status == .completed else { throw reader.error ?? MediaError.exportUnavailable }
        sourceFile = nil
        // Close the writer before scheduling its finalized PCM frames.
        let input = try AVAudioFile(forReading: sourceURL)
        guard input.length > 0, input.length <= Int64(UInt32.max) else { throw MediaError.exportUnavailable }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let speed: AVAudioNode
        if clip.preservesPitch {
            let pitch = AVAudioUnitTimePitch(); pitch.rate = Float(clip.speed); speed = pitch
        } else {
            let variable = AVAudioUnitVarispeed(); variable.rate = Float(clip.speed); speed = variable
        }
        engine.attach(player); engine.attach(speed)
        engine.connect(player, to: speed, format: input.processingFormat)
        engine.connect(speed, to: engine.mainMixerNode, format: input.processingFormat)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        player.scheduleSegment(input, startingFrame: 0, frameCount: AVAudioFrameCount(input.length), at: nil, completionHandler: {})
        try engine.start(); player.play()
        defer { player.stop(); engine.stop() }
        var result: AVAudioFile? = try AVAudioFile(forWriting: outputURL, settings: format.settings.merging([AVLinearPCMIsNonInterleaved: false]) { _, new in new })
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        let wanted = Int64((clip.duration.seconds * 48000).rounded())
        var written: Int64 = 0
        var retries = 0
        do {
            while written < wanted {
                try Task.checkCancellation()
                let count = AVAudioFrameCount(min(4096, wanted - written))
                switch try engine.renderOffline(count, to: buffer) {
                case .success, .insufficientDataFromInputNode:
                    try result!.write(from: buffer); written += Int64(buffer.frameLength); retries = 0
                case .cannotDoInCurrentContext:
                    retries += 1
                    if retries > 100 { throw MediaError.exportUnavailable }
                case .error: throw MediaError.exportUnavailable
                @unknown default: throw MediaError.exportUnavailable
                }
                if buffer.frameLength == 0 { throw MediaError.exportUnavailable }
            }
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
        result = nil
        if FileManager.default.fileExists(atPath: cachedURL.path) { try? FileManager.default.removeItem(at: outputURL) }
        else { try FileManager.default.moveItem(at: outputURL, to: cachedURL) }
        return cachedURL
    }
}
