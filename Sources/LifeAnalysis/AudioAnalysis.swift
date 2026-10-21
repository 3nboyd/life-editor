import Foundation
@preconcurrency import AVFoundation
import Accelerate

public struct AudioFingerprint: Sendable {
    public let values: [Float]
    public let samplesPerSecond: Double
    public init(values:[Float],samplesPerSecond:Double) {self.values=values;self.samplesPerSecond=samplesPerSecond}
}
public struct BeatEstimate: Sendable {
    public let bpm: Double
    public let offset: Double
    public let confidence: Double
}
public struct SyncEstimate: Sendable {
    /// Add this to the other recording's sequence start to match the reference.
    public let offset: Double
    public let confidence: Double
}
public enum AnalysisError: LocalizedError {
    case noAudio, unreadable, cancelled
    public var errorDescription:String? {
        switch self {case .noAudio:return "No audio stream.";case .unreadable:return "Audio analysis could not decode this recording.";case .cancelled:return "Analysis cancelled."}
    }
}

/// Serial background decoding bounds simultaneous readers and peak memory.
public actor AudioAnalyzer {
    public init() {}
    public func fingerprint(url:URL) async throws -> AudioFingerprint {
        let asset=AVURLAsset(url:url)
        guard let track=try await asset.loadTracks(withMediaType:.audio).first else{throw AnalysisError.noAudio}
        let reader=try AVAssetReader(asset:asset)
        let output=AVAssetReaderTrackOutput(track:track,outputSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVLinearPCMIsFloatKey:true,AVLinearPCMBitDepthKey:32,AVLinearPCMIsNonInterleaved:false,AVSampleRateKey:22050,AVNumberOfChannelsKey:1])
        output.alwaysCopiesSampleData=false
        reader.add(output)
        guard reader.startReading() else{throw reader.error ?? AnalysisError.unreadable}
        let fft=SpectralOnset()
        var result:[Float]=[]
        var block:[Float]=[];block.reserveCapacity(1024)
        while let buffer=output.copyNextSampleBuffer() {
            if Task.isCancelled {reader.cancelReading();throw CancellationError()}
            guard let data=CMSampleBufferGetDataBuffer(buffer) else{continue}
            let count=CMBlockBufferGetDataLength(data)/4
            guard count>0 else{continue}
            var samples=[Float](repeating:0,count:count)
            let status=samples.withUnsafeMutableBytes {CMBlockBufferCopyDataBytes(data,atOffset:0,dataLength:count*4,destination:$0.baseAddress!)}
            guard status==kCMBlockBufferNoErr else{throw AnalysisError.unreadable}
            for sample in samples {
                block.append(sample)
                if block.count==1024 {
                    result.append(fft.process(block))
                    block.removeFirst(512)
                }
            }
            // 24h of compact analysis is the document limit; never retain raw recording samples.
            guard result.count<4_000_000 else{reader.cancelReading();throw AnalysisError.unreadable}
        }
        guard reader.status == .completed else{throw reader.error ?? AnalysisError.unreadable}
        return AudioFingerprint(values:result,samplesPerSecond:22050.0/512)
    }
    public nonisolated static func beats(_ fingerprint:AudioFingerprint) -> BeatEstimate? {
        let values=fingerprint.values
        let rate=fingerprint.samplesPerSecond
        guard rate>0,values.count>Int(rate*4),let maximum=values.max(),maximum>0.000001 else{return nil}
        let minLag=max(1,Int(rate*60/200)),maxLag=min(values.count/2,Int(rate*60/50))
        guard minLag<maxLag else{return nil}
        var bestLag=0,best:Double=0
        for lag in minLag...maxLag {
            if Task.isCancelled{return nil}
            let n=values.count-lag
            var dot:Float=0,left:Float=0,right:Float=0
            values.withUnsafeBufferPointer { p in
                vDSP_dotpr(p.baseAddress!,1,p.baseAddress!+lag,1,&dot,vDSP_Length(n))
                vDSP_svesq(p.baseAddress!,1,&left,vDSP_Length(n));vDSP_svesq(p.baseAddress!+lag,1,&right,vDSP_Length(n))
            }
            let score=Double(dot)/max(1e-20,sqrt(Double(left)*Double(right)))
            if score>best {best=score;bestLag=lag}
        }
        guard bestLag>0 else{return nil}
        var phase=0,phaseScore:Float=0
        for candidate in 0..<bestLag {
            if Task.isCancelled{return nil}
            let score=stride(from:candidate,to:values.count,by:bestLag).reduce(Float(0)){$0+values[$1]}
            if score>phaseScore {phaseScore=score;phase=candidate}
        }
        return BeatEstimate(bpm:60*rate/Double(bestLag),offset:Double(phase)/rate,confidence:min(1,max(0,best)))
    }
    /// Normalized waveform-onset matching. Ambiguous/silent audio has low confidence.
    public nonisolated static func synchronize(reference:AudioFingerprint,other:AudioFingerprint,maxOffset:Double=60) -> SyncEstimate? {
        guard reference.samplesPerSecond==other.samplesPerSecond,reference.samplesPerSecond>0 else{return nil}
        let a=reference.values,b=other.values,rate=reference.samplesPerSecond
        let maxLag=min(Int(max(0,min(120,maxOffset))*rate),max(a.count,b.count))
        guard min(a.count,b.count)>Int(rate*2) else{return nil}
        var best:Double=0,offset=0
        var scores:[(Int,Double)]=[]
        for lag in -maxLag...maxLag {
            if Task.isCancelled{return nil}
            let aStart=max(0,lag),bStart=max(0,-lag)
            let n=min(13000,a.count-aStart,b.count-bStart)
            guard n>Int(rate*2) else{continue}
            var dot:Float=0,aa:Float=0,bb:Float=0
            a.withUnsafeBufferPointer { pa in b.withUnsafeBufferPointer {pb in
                let x=pa.baseAddress!+aStart,y=pb.baseAddress!+bStart
                vDSP_dotpr(x,1,y,1,&dot,vDSP_Length(n));vDSP_svesq(x,1,&aa,vDSP_Length(n));vDSP_svesq(y,1,&bb,vDSP_Length(n))
            }}
            let score=Double(dot)/max(1e-20,sqrt(Double(aa)*Double(bb)))
            scores.append((lag,score))
            if score>best {best=score;offset=lag}
        }
        guard best>0.1 else{return nil}
        let second=scores.filter{abs($0.0-offset)>max(2,Int(rate*0.1))}.map(\.1).max() ?? 0
        let specificity=min(1,max(0,(best-second)/max(0.1,best))*2)
        return SyncEstimate(offset:Double(offset)/rate,confidence:min(1,best)*specificity)
    }
}

private final class SpectralOnset {
    let setup:FFTSetup
    var real=[Float](repeating:0,count:512),imaginary=[Float](repeating:0,count:512)
    var previous=[Float](repeating:0,count:512),window=[Float](repeating:0,count:1024)
    init(){setup=vDSP_create_fftsetup(10,FFTRadix(kFFTRadix2))!;vDSP_hann_window(&window,1024,Int32(vDSP_HANN_NORM))}
    deinit{vDSP_destroy_fftsetup(setup)}
    func process(_ samples:[Float])->Float {
        var input=[Float](repeating:0,count:1024)
        vDSP_vmul(samples,1,window,1,&input,1,1024)
        var flux:Float=0
        real.withUnsafeMutableBufferPointer {r in imaginary.withUnsafeMutableBufferPointer {i in
            var split=DSPSplitComplex(realp:r.baseAddress!,imagp:i.baseAddress!)
            input.withUnsafeBufferPointer {p in p.baseAddress!.withMemoryRebound(to:DSPComplex.self,capacity:512) {vDSP_ctoz($0,2,&split,1,512)}}
            vDSP_fft_zrip(setup,&split,1,10,FFTDirection(FFT_FORWARD))
            for bin in 1..<512 {
                let magnitude=log1p(hypot(r[bin],i[bin]))
                flux+=max(0,magnitude-previous[bin]);previous[bin]=magnitude
            }
        }}
        return flux/511
    }
}
