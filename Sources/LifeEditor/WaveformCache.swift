import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import Accelerate
import CryptoKit
import LifeAnalysis

struct WaveformOverview:Sendable { let sourceKey:String;let pyramid:WaveformPyramid }
struct WaveformSampleWindow:Sendable {
    let sourceKey:String;let sampleRate:Double;let firstSample:Int64;let channels:[[Float]]
    var lastSample:Int64 { firstSample+Int64(channels.first?.count ?? 0) }
    var memoryBytes:Int { channels.reduce(0){$0+$1.count*4} }
}
enum WaveformCacheError:Error,Equatable { case noAudio,invalidSource,sourceChanged,windowTooLarge,decodeFailed }

/// One actor-owned reader at a time. All work is off the main actor; caller cancellation stops decoding.
actor WaveformCache {
    static let shared=WaveformCache()
    private let directory:URL
    private var summaries:[String:WaveformOverview]=[:]
    private var windows:[String:WaveformSampleWindow]=[:]
    init(root:URL? = nil) { directory=root ?? FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("org.lifeeditor.waveforms",isDirectory:true) }
    nonisolated static func sourceKey(for url:URL)throws->String {
        guard url.isFileURL else{throw WaveformCacheError.invalidSource}
        let values=try url.standardizedFileURL.resolvingSymlinksInPath().resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey,.isRegularFileKey])
        guard values.isRegularFile == true,let size=values.fileSize,let modified=values.contentModificationDate else{throw WaveformCacheError.invalidSource}
        let text="waveform-v2|\(url.standardizedFileURL.resolvingSymlinksInPath().path)|\(size)|\(modified.timeIntervalSince1970.bitPattern)"
        return SHA256.hash(data:Data(text.utf8)).map{String(format:"%02x",$0)}.joined()
    }
    func overview(for url:URL)async throws->WaveformOverview {
        try Task.checkCancellation()
        let key=try Self.sourceKey(for:url)
        if let cached=summaries[key]{return cached}
        let destination=directory.appendingPathComponent(key+".waveform")
        if let size=try? destination.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<=64_000_000,
           let data=try? Data(contentsOf:destination,options:.mappedIfSafe),let pyramid=try? WaveformPyramid.decode(data) {
            let cached=WaveformOverview(sourceKey:key,pyramid:pyramid);remember(cached);return cached
        }
        let metadata=try await format(url)
        try Task.checkCancellation()
        var base=256
        while ceil(metadata.duration*metadata.rate/Double(base))*Double(metadata.channels)>500_000 {base*=2}
        var builder=try WaveformPyramidBuilder(channelCount:metadata.channels,sampleRate:metadata.rate,baseSamplesPerBin:base)
        let reader=try AVAssetReader(asset:metadata.asset),output=makeOutput(metadata.track,rate:metadata.rate,channels:metadata.channels)
        guard reader.canAdd(output) else{throw WaveformCacheError.decodeFailed};reader.add(output)
        reader.timeRange=CMTimeRange(start:.zero,duration:CMTime(seconds:metadata.duration,preferredTimescale:600000))
        guard reader.startReading() else{throw WaveformCacheError.decodeFailed}
        defer{reader.cancelReading()}
        while let buffer=output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let samples=try pcm(buffer,channels:metadata.channels)
            let timestamp=CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            guard timestamp.isFinite,timestamp>=(-1),timestamp<=86400 else{throw WaveformCacheError.decodeFailed}
            var sourceStart=Int64((timestamp*metadata.rate).rounded())
            guard sourceStart>=(-Int64(metadata.rate)),sourceStart<=Int64(metadata.rate*86400) else{throw WaveformCacheError.decodeFailed}
            var skip=Int64(0)
            if sourceStart<builder.sampleCount {skip=min(Int64(samples.count/metadata.channels),builder.sampleCount-sourceStart);sourceStart+=skip}
            if sourceStart>builder.sampleCount {try builder.appendSilence(frames:sourceStart-builder.sampleCount)}
            if Int(skip)*metadata.channels<samples.count {try builder.append(interleaved:Array(samples.dropFirst(Int(skip)*metadata.channels)))}
        }
        try Task.checkCancellation();guard reader.status == .completed else{throw WaveformCacheError.decodeFailed}
        let pyramid=try builder.finish()
        guard try Self.sourceKey(for:url)==key else{throw WaveformCacheError.sourceChanged}
        let result=WaveformOverview(sourceKey:key,pyramid:pyramid)
        // Disk caches are disposable; a full or unavailable cache volume must not
        // discard an already decoded waveform needed for ordinary editing.
        let encoded=try pyramid.encoded()
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try encoded.write(to:destination,options:.atomic)
        } catch { /* Keep the bounded memory cache usable until storage recovers. */ }
        try Task.checkCancellation();remember(result)
        return result
    }
    /// Exact native-rate samples for a bounded source interval. Gaps remain zero; no resampling/downmixing.
    func samples(for url:URL,from lower:Double,to upper:Double)async throws->WaveformSampleWindow {
        try Task.checkCancellation()
        guard lower.isFinite,upper.isFinite,lower>=0,upper>lower,upper<=86400 else{throw WaveformCacheError.invalidSource}
        let key=try Self.sourceKey(for:url),metadata=try await format(url)
        let first=Int64(floor(lower*metadata.rate+0.000001)),last=min(Int64(ceil(upper*metadata.rate-0.000001)),Int64(ceil(metadata.duration*metadata.rate)))
        guard last>first,last-first<=262144 else{throw WaveformCacheError.windowTooLarge}
        let windowKey=key+"|\(first)|\(last)"
        if let cached=windows[windowKey]{return cached}
        let count=Int(last-first)
        var channels=[[Float]](repeating:[Float](repeating:0,count:count),count:metadata.channels)
        let reader=try AVAssetReader(asset:metadata.asset),output=makeOutput(metadata.track,rate:metadata.rate,channels:metadata.channels)
        guard reader.canAdd(output) else{throw WaveformCacheError.decodeFailed};reader.add(output)
        reader.timeRange=CMTimeRange(start:CMTime(seconds:Double(first)/metadata.rate,preferredTimescale:1_000_000_000),duration:CMTime(seconds:Double(last-first)/metadata.rate,preferredTimescale:1_000_000_000))
        guard reader.startReading() else{throw WaveformCacheError.decodeFailed};defer{reader.cancelReading()}
        while let buffer=output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let samples=try pcm(buffer,channels:metadata.channels),sampleFrames=samples.count/metadata.channels
            let timestamp=CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            guard timestamp.isFinite else{throw WaveformCacheError.decodeFailed}
            let sourceStart=Int64((timestamp*metadata.rate).rounded()),begin=max(first,sourceStart),end=min(last,sourceStart+Int64(sampleFrames))
            if end>begin {
                let inputOffset=Int(begin-sourceStart),outputOffset=Int(begin-first),length=Int(end-begin)
                samples.withUnsafeBufferPointer { source in
                    for channel in 0..<metadata.channels {
                        channels[channel].withUnsafeMutableBufferPointer { destination in
                            var zero:Float=0
                            vDSP_vsadd(source.baseAddress!+inputOffset*metadata.channels+channel,vDSP_Stride(metadata.channels),&zero,destination.baseAddress!+outputOffset,1,vDSP_Length(length))
                        }
                    }
                }
            }
        }
        try Task.checkCancellation();guard reader.status == .completed else{throw WaveformCacheError.decodeFailed}
        guard try Self.sourceKey(for:url)==key else{throw WaveformCacheError.sourceChanged}
        let result=WaveformSampleWindow(sourceKey:key,sampleRate:metadata.rate,firstSample:first,channels:channels)
        if windows.values.reduce(0,{$0+$1.memoryBytes})+result.memoryBytes>16_000_000 {windows.removeAll(keepingCapacity:true)}
        windows[windowKey]=result;return result
    }
    private func remember(_ overview:WaveformOverview) {
        if summaries.values.reduce(0,{$0+$1.pyramid.memoryBytes})+overview.pyramid.memoryBytes>48_000_000 {summaries.removeAll(keepingCapacity:true)}
        summaries[overview.sourceKey]=overview
    }
    private struct Format {var asset:AVURLAsset;var track:AVAssetTrack;var rate:Double;var channels:Int;var duration:Double}
    private func format(_ url:URL)async throws->Format {
        let asset=AVURLAsset(url:url)
        guard let track=try await asset.loadTracks(withMediaType:.audio).first else{throw WaveformCacheError.noAudio}
        let descriptions=try await track.load(.formatDescriptions)
        guard let description=descriptions.first,let stream=CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              stream.mSampleRate.isFinite,(8000...384000).contains(stream.mSampleRate),(1...8).contains(Int(stream.mChannelsPerFrame)) else{throw WaveformCacheError.invalidSource}
        let duration=try await asset.load(.duration).seconds
        guard duration.isFinite,duration>0,duration<=86400 else{throw WaveformCacheError.invalidSource}
        return Format(asset:asset,track:track,rate:stream.mSampleRate,channels:Int(stream.mChannelsPerFrame),duration:duration)
    }
    private func makeOutput(_ track:AVAssetTrack,rate:Double,channels:Int)->AVAssetReaderTrackOutput {
        let output=AVAssetReaderTrackOutput(track:track,outputSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVLinearPCMIsFloatKey:true,AVLinearPCMBitDepthKey:32,AVLinearPCMIsNonInterleaved:false,AVLinearPCMIsBigEndianKey:false,AVSampleRateKey:rate,AVNumberOfChannelsKey:channels]);output.alwaysCopiesSampleData=false;return output
    }
    private func pcm(_ buffer:CMSampleBuffer,channels:Int)throws->[Float] {
        guard let block=CMSampleBufferGetDataBuffer(buffer) else{throw WaveformCacheError.decodeFailed}
        let size=CMBlockBufferGetDataLength(block)
        guard size>0,size<=32_000_000,size%(4*channels)==0 else{throw WaveformCacheError.decodeFailed}
        var samples=[Float](repeating:0,count:size/4)
        let status=samples.withUnsafeMutableBytes{CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:size,destination:$0.baseAddress!)}
        guard status == kCMBlockBufferNoErr else{throw WaveformCacheError.decodeFailed};return samples
    }
}
