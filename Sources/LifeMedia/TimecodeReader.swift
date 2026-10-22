import Foundation
@preconcurrency import AVFoundation
import LifeCore

public enum TimecodeError:LocalizedError {
    case invalid,discontinuous,incompatible,resourceLimit
    public var errorDescription:String?{switch self{case .invalid:"The recording has invalid or unsupported timecode.";case .discontinuous:"The timecode contains a discontinuity. Use waveform or marker alignment.";case .incompatible:"The timecode formats differ. Use waveform or marker alignment.";case .resourceLimit:"The timecode track exceeds the analysis limit. Use waveform or marker alignment."}}
}
public struct TimecodeAlignment:Sendable,Equatable {
    public let offset:RationalTime
    public let requiresDayReview:Bool
}
public struct TimecodeReference:Sendable,Equatable {
    public let origin:RationalTime
    public let frameDuration:RationalTime
    public let frameQuanta:Int
    public let dropFrame:Bool
    public let wraps24Hours:Bool
    var dayDuration:RationalTime{
        let dropped=dropFrame ? (frameQuanta==60 ? 4:2)*54*24:0
        return frameDuration.scaled(by:Int64(frameQuanta*86400-dropped))
    }
    public func alignment(relativeTo reference:Self)throws->TimecodeAlignment{
        guard frameDuration==reference.frameDuration,frameQuanta==reference.frameQuanta,dropFrame==reference.dropFrame else{throw TimecodeError.incompatible}
        var difference=try origin.checkedSubtracting(reference.origin),review=false
        if wraps24Hours && reference.wraps24Hours,abs(difference.seconds)>dayDuration.seconds/2{
            difference=try difference.checkedAdding(dayDuration.checkedScaled(by:difference < .zero ? 1:-1));review=true
        }
        guard abs(difference.seconds)<=86400 else{throw TimecodeError.incompatible}
        return .init(offset:difference,requiresDayReview:review)
    }
}
struct TimecodeAccumulator {
    private(set) var reference:TimecodeReference?
    private var count=0
    mutating func append(frameNumber:Int64,at time:RationalTime,frameDuration:RationalTime,quanta:Int,flags:UInt32)throws{
        count+=1;guard count<=2_000_000 else{throw TimecodeError.resourceLimit}
        guard frameDuration > .zero,frameDuration.seconds<=1,frameDuration.timescale<=1_000_000_000,(1...240).contains(quanta),time >= .zero,time.seconds<=86400 else{throw TimecodeError.invalid}
        guard abs(1/frameDuration.seconds-Double(quanta))<0.25 else{throw TimecodeError.invalid}
        let drop=flags & kCMTimeCodeFlag_DropFrame != 0,wrap=flags & kCMTimeCodeFlag_24HourMax != 0
        guard frameNumber>=0 || flags & kCMTimeCodeFlag_NegTimesOK != 0 else{throw TimecodeError.invalid}
        if drop{guard (quanta==30 && frameDuration==RationalTime(value:1001,timescale:30000)) || (quanta==60 && frameDuration==RationalTime(value:1001,timescale:60000)) else{throw TimecodeError.invalid}}
        var origin=try frameDuration.checkedScaled(by:frameNumber).checkedSubtracting(time)
        let candidate=TimecodeReference(origin:origin,frameDuration:frameDuration,frameQuanta:quanta,dropFrame:drop,wraps24Hours:wrap)
        guard let first=reference else{reference=candidate;return}
        guard first.frameDuration==frameDuration,first.frameQuanta==quanta,first.dropFrame==drop,first.wraps24Hours==wrap else{throw TimecodeError.discontinuous}
        if wrap{
            let shift=((first.origin.seconds-origin.seconds)/first.dayDuration.seconds).rounded()
            guard abs(shift)<=2 else{throw TimecodeError.discontinuous}
            origin=try origin.checkedAdding(first.dayDuration.checkedScaled(by:Int64(shift)))
        }
        guard abs(try origin.checkedSubtracting(first.origin).seconds)<=frameDuration.seconds/4 else{throw TimecodeError.discontinuous}
    }
}

/// Reads original local timecode tracks; conversion proxies never become the source of truth.
/// Big-endian tmcd/tc64 sample formats follow Apple's Technical Note TN2310.
public actor TimecodeReader {
    public static let shared=TimecodeReader()
    public func read(_ url:URL)async throws->TimecodeReference?{
        guard url.isFileURL else{throw TimecodeError.invalid}
        try Task.checkCancellation()
        let asset=AVURLAsset(url:url),tracks=try await asset.loadTracks(withMediaType:.timecode)
        guard !tracks.isEmpty else{return nil}
        guard tracks.count==1 else{throw TimecodeError.invalid}
        let reader=try AVAssetReader(asset:asset),output=AVAssetReaderTrackOutput(track:tracks[0],outputSettings:nil)
        guard reader.canAdd(output) else{throw TimecodeError.invalid};reader.add(output)
        guard reader.startReading() else{throw reader.error ?? TimecodeError.invalid}
        defer{reader.cancelReading()}
        var accumulator=TimecodeAccumulator()
        while let sample=output.copyNextSampleBuffer(){
            try Task.checkCancellation()
            // AVFoundation emits empty edit-boundary buffers before timecode data.
            if CMSampleBufferGetNumSamples(sample)==0, CMSampleBufferGetDuration(sample) == .zero {continue}
            guard let format=CMSampleBufferGetFormatDescription(sample),let block=CMSampleBufferGetDataBuffer(sample) else{throw TimecodeError.invalid}
            let type=CMFormatDescriptionGetMediaSubType(format)
            let size:Int
            switch type{case kCMTimeCodeFormatType_TimeCode32:size=4;case kCMTimeCodeFormatType_TimeCode64:size=8;default:throw TimecodeError.invalid}
            let frames=CMSampleBufferGetNumSamples(sample)
            guard frames>0,frames<=2_000_000,CMBlockBufferGetDataLength(block)==frames*size else{throw TimecodeError.invalid}
            let duration=CMTimeCodeFormatDescriptionGetFrameDuration(format)
            guard duration.isNumeric,duration.timescale>0 else{throw TimecodeError.invalid}
            let frameDuration=RationalTime(value:duration.value,timescale:Int64(duration.timescale))
            let quanta=Int(CMTimeCodeFormatDescriptionGetFrameQuanta(format)),flags=CMTimeCodeFormatDescriptionGetTimeCodeFlags(format)
            var bytes=[UInt8](repeating:0,count:frames*size)
            let status=bytes.withUnsafeMutableBytes{CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:$0.count,destination:$0.baseAddress!)}
            guard status==kCMBlockBufferNoErr else{throw TimecodeError.invalid}
            for index in 0..<frames{
                try Task.checkCancellation()
                var info=CMSampleTimingInfo()
                guard CMSampleBufferGetSampleTimingInfo(sample,at:index,timingInfoOut:&info)==noErr,info.presentationTimeStamp.isNumeric,info.presentationTimeStamp.timescale>0 else{throw TimecodeError.invalid}
                let bits=bytes[(index*size)..<((index+1)*size)].reduce(UInt64(0)){($0<<8)|UInt64($1)}
                let number=size==4 ? Int64(Int32(bitPattern:UInt32(bits))):Int64(bitPattern:bits)
                try accumulator.append(frameNumber:number,at:.init(value:info.presentationTimeStamp.value,timescale:Int64(info.presentationTimeStamp.timescale)),frameDuration:frameDuration,quanta:quanta,flags:flags)
            }
        }
        guard reader.status == .completed else{throw reader.error ?? TimecodeError.invalid}
        return accumulator.reference
    }
}
