import Foundation
import AVFoundation
import CoreImage
import LifeCore

private struct FrozenFrameImage:@unchecked Sendable{let image:CIImage}

extension MediaPipeline {
    /// Reads timestamps, not pixels, in a bounded tail window; never guesses VFR frame positions.
    public func lastVideoFrameTime(asset:MediaAsset)async throws->RationalTime {
        guard asset.kind == .video else{throw MediaError.invalidRange(asset.url.lastPathComponent)}
        try Task.checkCancellation()
        // Required full-quality native conversions retain the source clock; editing proxies are never used.
        let url=asset.preparedURL ?? asset.url
        let job=Task.detached(priority:.userInitiated) {
            let source=AVURLAsset(url:url),duration=try await source.load(.duration)
            guard let track=try await source.loadTracks(withMediaType:.video).first else{throw MediaError.unsupported(url.lastPathComponent)}
            let reader=try AVAssetReader(asset:source),output=AVAssetReaderTrackOutput(track:track,outputSettings:nil)
            guard reader.canAdd(output) else{throw MediaError.unsupported(url.lastPathComponent)}
            reader.add(output);reader.timeRange=CMTimeRange(start:CMTimeMaximum(.zero,CMTimeSubtract(duration,CMTime(seconds:5,preferredTimescale:600000))),end:duration)
            guard reader.startReading() else{throw reader.error ?? MediaError.invalidRange(url.lastPathComponent)}
            defer{reader.cancelReading()}
            var last:CMTime?;var count=0
            while let sample=output.copyNextSampleBuffer(){
                try Task.checkCancellation()
                let samples=CMSampleBufferGetNumSamples(sample);count+=samples
                guard count<=20000 else{throw MediaError.invalidRange(url.lastPathComponent)}
                for index in 0..<samples {
                    var timing=CMSampleTimingInfo()
                    guard CMSampleBufferGetSampleTimingInfo(sample,at:index,timingInfoOut:&timing)==noErr else{throw MediaError.invalidRange(url.lastPathComponent)}
                    let time=timing.presentationTimeStamp
                    if time.isNumeric,CMTimeCompare(time,.zero)>=0,CMTimeCompare(time,duration)<0,last.map({CMTimeCompare(time,$0)>0}) ?? true {last=time}
                }
            }
            guard reader.status == .completed,let last else{throw reader.error ?? MediaError.invalidRange(url.lastPathComponent)}
            return RationalTime(value:last.value,timescale:Int64(last.timescale))
        }
        return try await withTaskCancellationHandler{try await job.value}onCancel:{job.cancel()}
    }
    func frozenFrameImage(asset:MediaAsset,time:RationalTime,size:CGSize)async throws->CIImage {
        let job=Task.detached(priority:.userInitiated){
            try Task.checkCancellation()
            let source=AVURLAsset(url:asset.preparedURL ?? asset.url)
            guard let track=try await source.loadTracks(withMediaType:.video).first else{throw MediaError.unsupported(asset.url.lastPathComponent)}
            let transform=try await track.load(.preferredTransform),reader=try AVAssetReader(asset:source)
            let output=AVAssetReaderTrackOutput(track:track,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,AVVideoColorPropertiesKey:[AVVideoColorPrimariesKey:AVVideoColorPrimaries_ITU_R_709_2,AVVideoTransferFunctionKey:AVVideoTransferFunction_ITU_R_709_2,AVVideoYCbCrMatrixKey:AVVideoYCbCrMatrix_ITU_R_709_2]])
            guard reader.canAdd(output) else{throw MediaError.unsupported(asset.url.lastPathComponent)}
            reader.add(output);reader.timeRange=CMTimeRange(start:time.cmTime,duration:CMTime(value:1,timescale:600000))
            guard reader.startReading() else{throw reader.error ?? MediaError.invalidRange(asset.url.lastPathComponent)}
            defer{reader.cancelReading()}
            try Task.checkCancellation()
            guard let sample=output.copyNextSampleBuffer(),let buffer=CMSampleBufferGetImageBuffer(sample),CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(sample),time.cmTime)==0 else{throw reader.error ?? MediaError.invalidRange(asset.url.lastPathComponent)}
            let image=CIImage(cvPixelBuffer:buffer).transformed(by:transform),extent=image.extent,scale=min(size.width/extent.width,size.height/extent.height)
            try Task.checkCancellation()
            return FrozenFrameImage(image:image.transformed(by:CGAffineTransform(translationX:-extent.minX,y:-extent.minY)).transformed(by:CGAffineTransform(scaleX:scale,y:scale)).transformed(by:CGAffineTransform(translationX:(size.width-extent.width*scale)/2,y:(size.height-extent.height*scale)/2)))
        }
        return try await withTaskCancellationHandler{(try await job.value).image}onCancel:{job.cancel()}
    }
}
