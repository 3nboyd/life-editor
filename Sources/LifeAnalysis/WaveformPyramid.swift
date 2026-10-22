import Foundation
import Accelerate
import CryptoKit

public enum WaveformError:Error,Equatable { case invalidFormat,invalidCache,resourceLimit }
public struct WaveformBin:Equatable,Sendable {
    public var minimum:Float;public var maximum:Float
    public init(minimum:Float,maximum:Float){self.minimum=minimum;self.maximum=maximum}
}
public struct WaveformLevel:Equatable,Sendable {
    public var samplesPerBin:Int64;public var channels:[[WaveformBin]]
    public init(samplesPerBin:Int64,channels:[[WaveformBin]]){self.samplesPerBin=samplesPerBin;self.channels=channels}
}
public struct WaveformPyramid:Equatable,Sendable {
    public var sampleRate:Double;public var sampleCount:Int64;public var levels:[WaveformLevel]
    public var channelCount:Int { levels.first?.channels.count ?? 0 }
    public var memoryBytes:Int { levels.reduce(0){$0+$1.channels.reduce(0){$0+$1.count*8}} }
    public init(sampleRate:Double,sampleCount:Int64,levels:[WaveformLevel]){self.sampleRate=sampleRate;self.sampleCount=sampleCount;self.levels=levels}
    public func level(samplesPerPixel:Double)->WaveformLevel? { levels.last(where:{Double($0.samplesPerBin)<=max(1,samplesPerPixel)}) ?? levels.first }
    public func encoded()throws->Data {
        guard isValid else {throw WaveformError.invalidCache}
        var data=Data("LFWAVE02".utf8)
        func append<T:FixedWidthInteger>(_ value:T){var little=value.littleEndian;withUnsafeBytes(of:&little){data.append(contentsOf:$0)}}
        append(sampleRate.bitPattern);append(UInt64(sampleCount));append(UInt32(channelCount));append(UInt32(levels.count))
        for level in levels {
            append(UInt64(level.samplesPerBin));append(UInt32(level.channels[0].count))
            for channel in level.channels {for bin in channel {append(bin.minimum.bitPattern);append(bin.maximum.bitPattern)}}
        }
        data.append(contentsOf:SHA256.hash(data:data))
        return data
    }
    public static func decode(_ encoded:Data)throws->WaveformPyramid {
        guard encoded.count>=64,encoded.count<=64_000_000 else{throw WaveformError.invalidCache}
        let data=Data(encoded.dropLast(32))
        guard Data(SHA256.hash(data:data))==Data(encoded.suffix(32)) else{throw WaveformError.invalidCache}
        guard data.count<=64_000_000,data.count>=32,String(data:Data(data.prefix(8)),encoding:.utf8)=="LFWAVE02" else{throw WaveformError.invalidCache}
        var cursor=8
        func read<T:FixedWidthInteger>(_ type:T.Type)throws->T {
            guard cursor+MemoryLayout<T>.size<=data.count else{throw WaveformError.invalidCache}
            let value=data.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:cursor,as:T.self)};cursor+=MemoryLayout<T>.size;return T(littleEndian:value)
        }
        let rate=Double(bitPattern:try read(UInt64.self)),count=try read(UInt64.self),channels=Int(try read(UInt32.self)),levelCount=Int(try read(UInt32.self))
        guard (1...8).contains(channels),(1...32).contains(levelCount),count<=Int64.max else{throw WaveformError.invalidCache}
        var levels:[WaveformLevel]=[],totalBins=0
        for _ in 0..<levelCount {
            let stride=try read(UInt64.self),bins=Int(try read(UInt32.self))
            guard stride>0,stride<=Int64.max,bins>0,bins<=2_000_000,channels*bins*8<=data.count-cursor else{throw WaveformError.invalidCache}
            totalBins+=channels*bins;guard totalBins<=4_000_000 else{throw WaveformError.resourceLimit}
            var values=[[WaveformBin]]();values.reserveCapacity(channels)
            for _ in 0..<channels {var channel:[WaveformBin]=[];channel.reserveCapacity(bins);for _ in 0..<bins {channel.append(WaveformBin(minimum:Float(bitPattern:try read(UInt32.self)),maximum:Float(bitPattern:try read(UInt32.self))))};values.append(channel)}
            levels.append(WaveformLevel(samplesPerBin:Int64(stride),channels:values))
        }
        let result=WaveformPyramid(sampleRate:rate,sampleCount:Int64(count),levels:levels)
        guard cursor==data.count,result.isValid else{throw WaveformError.invalidCache};return result
    }
    public var isValid:Bool {
        guard sampleRate.isFinite,(8000...384000).contains(sampleRate),sampleCount>0,sampleCount<=Int64(sampleRate*86400),(1...8).contains(channelCount),!levels.isEmpty,levels.count<=32,memoryBytes<=32_000_000 else{return false}
        var previous:Int64=0
        for level in levels {
            guard level.samplesPerBin>previous,level.samplesPerBin<=Int64.max/2,level.channels.count==channelCount else{return false}
            let expected=Int((sampleCount+level.samplesPerBin-1)/level.samplesPerBin)
            guard level.channels.allSatisfy({$0.count==expected && $0.allSatisfy{$0.minimum.isFinite && $0.maximum.isFinite && $0.minimum<=$0.maximum}}) else{return false}
            previous=level.samplesPerBin
        }
        return true
    }
}
/// Streaming min/max aggregation preserves channel polarity and peaks; no full recording PCM is retained.
public struct WaveformPyramidBuilder:Sendable {
    public let channelCount:Int;public let sampleRate:Double;public let baseSamplesPerBin:Int
    public private(set) var sampleCount:Int64=0
    private var channels:[[WaveformBin]];private var minimum:[Float];private var maximum:[Float];private var pending=0
    public init(channelCount:Int,sampleRate:Double,baseSamplesPerBin:Int=256)throws {
        guard (1...8).contains(channelCount),sampleRate.isFinite,(8000...384000).contains(sampleRate),(1...1_048_576).contains(baseSamplesPerBin) else{throw WaveformError.invalidFormat}
        self.channelCount=channelCount;self.sampleRate=sampleRate;self.baseSamplesPerBin=baseSamplesPerBin
        channels=Array(repeating:[],count:channelCount);minimum=Array(repeating:0,count:channelCount);maximum=minimum
    }
    public mutating func append(interleaved:[Float])throws {
        guard interleaved.count%channelCount==0,interleaved.count<=8_388_608 else{throw WaveformError.invalidFormat}
        let frameCount=interleaved.count/channelCount
        guard sampleCount+Int64(frameCount)<=Int64(sampleRate*86400) else{throw WaveformError.resourceLimit}
        try interleaved.withUnsafeBufferPointer { samples in
            var frame=0
            while frame<frameCount {
                let count=min(baseSamplesPerBin-pending,frameCount-frame)
                for channel in 0..<channelCount {
                    var low:Float=0,high:Float=0
                    vDSP_minv(samples.baseAddress!+frame*channelCount+channel,vDSP_Stride(channelCount),&low,vDSP_Length(count))
                    vDSP_maxv(samples.baseAddress!+frame*channelCount+channel,vDSP_Stride(channelCount),&high,vDSP_Length(count))
                    guard low.isFinite,high.isFinite else{throw WaveformError.invalidFormat}
                    minimum[channel]=pending == 0 ? low:min(minimum[channel],low);maximum[channel]=pending == 0 ? high:max(maximum[channel],high)
                }
                pending+=count;sampleCount+=Int64(count);frame+=count
                if pending==baseSamplesPerBin {try finishBin()}
            }
        }
    }
    public mutating func appendSilence(frames:Int64)throws {
        guard frames>=0 else{throw WaveformError.invalidFormat}
        let block=[Float](repeating:0,count:4096*channelCount)
        var remaining=frames
        while remaining>0 {try Task.checkCancellation();let take=min(4096,remaining);try append(interleaved:take==4096 ? block:Array(block.prefix(Int(take)*channelCount)));remaining-=take}
    }
    public mutating func finish()throws->WaveformPyramid {
        if pending>0 {try finishBin()}
        guard sampleCount>0 else{throw WaveformError.invalidFormat}
        var levels=[WaveformLevel(samplesPerBin:Int64(baseSamplesPerBin),channels:channels)]
        while let last=levels.last,last.channels[0].count>1 {
            try Task.checkCancellation()
            let next=last.channels.map { bins in stride(from:0,to:bins.count,by:2).map { index in
                guard index+1<bins.count else{return bins[index]};return WaveformBin(minimum:min(bins[index].minimum,bins[index+1].minimum),maximum:max(bins[index].maximum,bins[index+1].maximum))
            }}
            levels.append(WaveformLevel(samplesPerBin:last.samplesPerBin*2,channels:next))
        }
        let result=WaveformPyramid(sampleRate:sampleRate,sampleCount:sampleCount,levels:levels)
        guard result.isValid else{throw WaveformError.resourceLimit};return result
    }
    private mutating func finishBin()throws {
        guard (channels[0].count+1)*channelCount<=2_000_000 else{throw WaveformError.resourceLimit}
        for channel in 0..<channelCount {channels[channel].append(WaveformBin(minimum:minimum[channel],maximum:maximum[channel]))};pending=0
    }
}
