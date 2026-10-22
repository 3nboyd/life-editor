import Foundation
import CoreGraphics
import CryptoKit
import LifeCore
import LifeMedia

struct TimelineThumbnailCell:Equatable,Sendable {
    let clipID:UUID;let offsetPixels:Double;let widthPixels:Double;let sourceTime:RationalTime
}
enum FilmstripPlanner {
    /// Work scales with visible screen cells, never with total recording duration.
    static func cells(clip:Clip,assetKind:AssetKind,visibleRange:ClosedRange<Double>,pixelsPerSecond:Double,tileWidth:Double=112,maximumCount:Int=24)->[TimelineThumbnailCell] {
        guard assetKind != .audio,pixelsPerSecond.isFinite,pixelsPerSecond>0,tileWidth.isFinite,tileWidth>=24,maximumCount>0,
              visibleRange.lowerBound.isFinite,visibleRange.upperBound.isFinite,clip.duration.seconds>0 else{return []}
        let lower=max(clip.start.seconds,visibleRange.lowerBound),upper=min(clip.end.seconds,visibleRange.upperBound)
        guard upper>lower else{return []}
        let first=max(0,Int(floor((lower-clip.start.seconds)*pixelsPerSecond/tileWidth))),last=max(0,Int(ceil((upper-clip.start.seconds)*pixelsPerSecond/tileWidth))-1)
        guard last>=first else{return []}
        return (first...min(last,first+min(maximumCount,128)-1)).compactMap{index in
            let offset=Double(index)*tileWidth,width=min(tileWidth,clip.duration.seconds*pixelsPerSecond-offset)
            guard width>0 else{return nil}
            let timeline=clip.start.seconds+(offset+width/2)/pixelsPerSecond
            let time=RationalTime(value:Int64((timeline*600000).rounded()),timescale:600000)
            guard let source=try? clip.checkedSourceTime(at:time) else{return nil}
            return TimelineThumbnailCell(clipID:clip.id,offsetPixels:offset,widthPixels:width,sourceTime:assetKind == .image ? .zero:source)
        }
    }
}
/// CGImage is immutable; this wrapper never exposes a mutable backing buffer.
struct TimelineThumbnail: @unchecked Sendable { let key:String;let image:CGImage }
enum TimelineThumbnailError:Error {case invalidSource,tooManyRequests,sourceChanged}

/// Global decoder admission is bounded even when several project windows are open.
actor TimelineThumbnailCache {
    static let shared=TimelineThumbnailCache()
    private struct Entry { let result:TimelineThumbnail;let bytes:Int;var access:UInt64 }
    private var entries:[String:Entry]=[:]
    private var clock:UInt64=0
    private var running=0
    private var queue:[UUID]=[]
    private var waiting:[UUID:CheckedContinuation<Void,any Error>]=[:]
    let budgetBytes:Int
    init(budgetBytes:Int=48_000_000){self.budgetBytes=max(256000,budgetBytes)}
    nonisolated static func key(asset:MediaAsset,sourceTime:RationalTime,effects:[EffectInstance])throws->String {
        let source=try WaveformCache.sourceKey(for:asset.preparedURL ?? asset.url)
        return try logicalKey(sourceStamp:source,sourceTime:sourceTime,effects:effects)
    }
    nonisolated static func logicalKey(sourceStamp:String,sourceTime:RationalTime,effects:[EffectInstance])throws->String {
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        var data=Data("filmstrip-v1|\(sourceStamp)|\(sourceTime.value)/\(sourceTime.timescale)|".utf8)
        data.append(try encoder.encode(effects))
        return SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
    }
    func sourceStamp(for asset:MediaAsset)throws->String {try WaveformCache.sourceKey(for:asset.preparedURL ?? asset.url)}
    func image(for asset:MediaAsset,sourceTime:RationalTime,effects:[EffectInstance]=[])async throws->TimelineThumbnail {
        try Task.checkCancellation()
        let key=try Self.key(asset:asset,sourceTime:sourceTime,effects:effects)
        clock &+= 1
        if var cached=entries[key]{cached.access=clock;entries[key]=cached;return cached.result}
        try await acquire();defer{release()}
        try Task.checkCancellation()
        if var cached=entries[key]{cached.access=clock;entries[key]=cached;return cached.result}
        let original=try await MediaPipeline().thumbnail(asset:asset,at:sourceTime,effects:effects)
        try Task.checkCancellation()
        guard try Self.key(asset:asset,sourceTime:sourceTime,effects:effects)==key else{throw TimelineThumbnailError.sourceChanged}
        let image=try bounded(original),result=TimelineThumbnail(key:key,image:image),bytes=image.bytesPerRow*image.height
        while entries.values.reduce(0,{$0+$1.bytes})+bytes>budgetBytes,let oldest=entries.min(by:{$0.value.access<$1.value.access})?.key {entries.removeValue(forKey:oldest)}
        clock &+= 1;entries[key]=Entry(result:result,bytes:bytes,access:clock);return result
    }
    var memoryBytes:Int {entries.values.reduce(0){$0+$1.bytes}}
    var activeJobs:Int {running}
    private func bounded(_ image:CGImage)throws->CGImage {
        let ratio=min(1,min(320/Double(image.width),180/Double(image.height)))
        guard ratio<1 else{return image}
        let width=max(1,Int((Double(image.width)*ratio).rounded())),height=max(1,Int((Double(image.height)*ratio).rounded()))
        guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{throw TimelineThumbnailError.invalidSource}
        context.interpolationQuality = .high;context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        guard let result=context.makeImage() else{throw TimelineThumbnailError.invalidSource};return result
    }
    private func acquire()async throws {
        try Task.checkCancellation()
        if running<2{running+=1;return}
        guard waiting.count<64 else{throw TimelineThumbnailError.tooManyRequests}
        let id=UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation{(continuation:CheckedContinuation<Void,any Error>) in queue.append(id);waiting[id]=continuation}
        } onCancel:{Task{await self.cancelWaiter(id)}}
    }
    private func cancelWaiter(_ id:UUID){queue.removeAll{$0==id};waiting.removeValue(forKey:id)?.resume(throwing:CancellationError())}
    private func release(){
        while !queue.isEmpty {let id=queue.removeFirst();if let next=waiting.removeValue(forKey:id){next.resume();return}}
        running-=1
    }
}
