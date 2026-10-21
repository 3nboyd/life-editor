import Foundation
@preconcurrency import AVFoundation
import CoreMedia

/// A bounded display-only peak summary. No generated audio data is written to the project.
actor WaveformCache {
    static let shared = WaveformCache()
    private var entries: [URL: [Float]] = [:]
    func peaks(for url: URL) async -> [Float] {
        if let entry=entries[url] { return entry }
        do {
            let asset=AVURLAsset(url:url)
            guard let track=try await asset.loadTracks(withMediaType:.audio).first else {return []}
            let duration=try await asset.load(.duration).seconds
            guard duration.isFinite,duration>0 else{return []}
            let reader=try AVAssetReader(asset:asset)
            let output=AVAssetReaderTrackOutput(track:track,outputSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVLinearPCMIsFloatKey:true,AVLinearPCMBitDepthKey:32,AVLinearPCMIsNonInterleaved:false,AVSampleRateKey:8000,AVNumberOfChannelsKey:1])
            output.alwaysCopiesSampleData=false
            reader.add(output);guard reader.startReading() else{return []}
            let bucketCount=2048
            var peaks=[Float](repeating:0,count:bucketCount)
            var sampleIndex=0
            while let buffer=output.copyNextSampleBuffer() {
                if Task.isCancelled {reader.cancelReading();return []}
                guard let block=CMSampleBufferGetDataBuffer(buffer) else{continue}
                let count=CMBlockBufferGetDataLength(block)/MemoryLayout<Float>.size
                var samples=[Float](repeating:0,count:count)
                let status=samples.withUnsafeMutableBytes{CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:count*4,destination:$0.baseAddress!)}
                if status == kCMBlockBufferNoErr {
                    for sample in samples {
                        let bucket=min(bucketCount-1,Int(Double(sampleIndex)/(duration*8000)*Double(bucketCount)))
                        peaks[bucket]=max(peaks[bucket],abs(sample));sampleIndex+=1
                    }
                }
            }
            guard reader.status == .completed else{return []}
            if entries.count>=24 {entries.removeAll(keepingCapacity:true)}
            entries[url]=peaks;return peaks
        } catch {return []}
    }
}
