import Foundation
@preconcurrency import AVFoundation
import LifeCore

/// Immutable view of a prepared playback mix. Retaining its item also retains required cache leases.
public final class PlaybackMeterSource:@unchecked Sendable {
    let item:AVPlayerItem
    let asset:AVAsset
    let mix:AVAudioMix?
    let mixIdentity:ObjectIdentifier?
    private let observedMix:AVAudioMix?
    @MainActor public init(item:AVPlayerItem){self.item=item;asset=item.asset;let current=item.audioMix;observedMix=current;mixIdentity=current.map(ObjectIdentifier.init);mix=current?.copy() as? AVAudioMix}
    @MainActor public func matches(_ item:AVPlayerItem)->Bool{self.item === item && mixIdentity==item.audioMix.map(ObjectIdentifier.init)}
}
public struct PlaybackMeterReading:Sendable,Equatable {
    public let frame:AudioMeterFrame
    public let sampleCount:Int
    public let elapsedSeconds:Double
}
private actor MeterAdmission {
    static let shared=MeterAdmission()
    private var busy=false
    private var order:[UUID]=[]
    private var waiting:[UUID:CheckedContinuation<Void,any Error>]=[:]
    func acquire()async throws{
        try Task.checkCancellation();if !busy{busy=true;return}
        guard waiting.count<16 else{throw MediaError.exportUnavailable};let id=UUID()
        try await withTaskCancellationHandler{try await withCheckedThrowingContinuation{(continuation:CheckedContinuation<Void,any Error>) in order.append(id);waiting[id]=continuation}}onCancel:{Task{await self.cancel(id)}}
    }
    private func cancel(_ id:UUID){order.removeAll{$0==id};waiting.removeValue(forKey:id)?.resume(throwing:CancellationError())}
    func release(){while !order.isEmpty{let id=order.removeFirst();if let next=waiting.removeValue(forKey:id){next.resume();return}};busy=false}
}
public enum PlaybackAudioMeter {
    /// Project-mix sample peaks, before device/system volume; never normalizes or limits samples.
    public static func read(_ source:PlaybackMeterSource,at time:RationalTime)async throws->PlaybackMeterReading {
        guard time >= .zero,time.timescale<=1_000_000_000,time.seconds<=86400 else{throw MediaError.invalidRange("Meter position")}
        try await MeterAdmission.shared.acquire()
        do{let result=try await perform(source,at:time);await MeterAdmission.shared.release();return result}
        catch{await MeterAdmission.shared.release();throw error}
    }
    private static func perform(_ source:PlaybackMeterSource,at time:RationalTime)async throws->PlaybackMeterReading {
        try Task.checkCancellation()
        let task=Task.detached(priority:.utility){
            let began=ContinuousClock.now
            try Task.checkCancellation()
            let center=CMTimeConvertScale(CMTime(value:time.value,timescale:CMTimeScale(clamping:time.timescale)),timescale:48000,method:.roundHalfAwayFromZero).value
            let first=max(0,center-2400),last=first+4800
            let tracks=try await source.asset.loadTracks(withMediaType:.audio)
            if tracks.isEmpty{return PlaybackMeterReading(frame:.init(time:time,leftDBFS:-.infinity,rightDBFS:-.infinity),sampleCount:0,elapsedSeconds:0)}
            let reader=try AVAssetReader(asset:source.asset)
            let output=AVAssetReaderAudioMixOutput(audioTracks:tracks,audioSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:48000,AVNumberOfChannelsKey:2,AVLinearPCMBitDepthKey:32,AVLinearPCMIsFloatKey:true,AVLinearPCMIsNonInterleaved:false])
            output.audioMix=source.mix;output.alwaysCopiesSampleData=false
            guard reader.canAdd(output) else{throw MediaError.exportUnavailable};reader.add(output)
            reader.timeRange=CMTimeRange(start:CMTime(value:first,timescale:48000),duration:CMTime(value:4800,timescale:48000))
            let io=BlockingAssetReader(reader:reader,output:output,label:"org.lifeeditor.meter.read")
            return try await withTaskCancellationHandler{
                do{
                    try await io.start()
                    var left=Float(0),right=Float(0),count=0,buffers=0
                    while let sample=try await io.next().buffer{
                        try Task.checkCancellation();buffers+=1
                        guard buffers<=64 else{throw MediaError.exportUnavailable}
                        let frames=CMSampleBufferGetNumSamples(sample)
                        if frames==0{continue}
                        guard buffers<=64,frames>=0,frames<=32768,let block=CMSampleBufferGetDataBuffer(sample),CMBlockBufferGetDataLength(block)>=frames*8 else{throw MediaError.exportUnavailable}
                        let position=CMTimeConvertScale(CMSampleBufferGetPresentationTimeStamp(sample),timescale:48000,method:.roundHalfAwayFromZero).value
                        var values=[Float](repeating:0,count:frames*2)
                        let status=values.withUnsafeMutableBytes{CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:frames*8,destination:$0.baseAddress!)}
                        guard status==noErr else{throw MediaError.exportUnavailable}
                        for index in 0..<frames where position+Int64(index)>=first && position+Int64(index)<last {
                            let l=values[index*2],r=values[index*2+1];guard l.isFinite,r.isFinite else{throw MediaError.unsupported("Non-finite audio samples")}
                            left=max(left,abs(l));right=max(right,abs(r));count+=1
                            guard count<=4800 else{throw MediaError.exportUnavailable}
                        }
                    }
                    try await io.requireCompleted()
                    let duration=began.duration(to:.now),elapsed=Double(duration.components.seconds)+Double(duration.components.attoseconds)/1e18
                    func db(_ value:Float)->Double{value>0 ? 20*log10(Double(value)):-.infinity}
                    return PlaybackMeterReading(frame:.init(time:time,leftDBFS:db(left),rightDBFS:db(right)),sampleCount:count,elapsedSeconds:elapsed)
                }catch{await io.cancelAndWait();throw error}
            }onCancel:{io.cancel()}
        }
        return try await withTaskCancellationHandler{try await task.value}onCancel:{task.cancel()}
    }
}
