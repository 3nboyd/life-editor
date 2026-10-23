import Foundation
@preconcurrency import AVFoundation
import LifeCore

public enum CamcorderRecordingDate {
    /// Content-creation metadata is an offered candidate, never proof of capture
    /// time and never automatically applied. Filesystem dates are not consulted.
    public static func candidate(for asset:MediaAsset)async throws->CamcorderDateOverlay? {
        try Task.checkCancellation()
        guard asset.url.isFileURL else{throw HelperError.localFilesOnly}
        let source=AVURLAsset(url:asset.url)
        let metadata=try await source.load(.metadata)
        var strings:[String]=[]
        for item in metadata where item.identifier == .quickTimeMetadataCreationDate {
            try Task.checkCancellation()
            if let text=try await item.load(.stringValue){strings.append(text)}
        }
        return candidate(from:strings)
    }
    static func candidate(from strings:[String])->CamcorderDateOverlay? {
        var result:CamcorderDateOverlay?
        for text in strings {
            guard let candidate=CamcorderDateOverlay.parse(text,origin:.recorded) else{continue}
            if let result,result.sourceZeroUnixSeconds != candidate.sourceZeroUnixSeconds || result.utcOffsetSeconds != candidate.utcOffsetSeconds{return nil}
            result=candidate
        }
        return result
    }
}
