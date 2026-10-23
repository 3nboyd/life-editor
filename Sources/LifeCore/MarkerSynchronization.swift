import Foundation

public struct MarkerAlignment:Sendable,Equatable {
    public let referenceAssetID:UUID
    public let targetAssetID:UUID
    /// Target source origin relative to the first reference clip's source origin.
    public let offset:RationalTime
}
public enum MarkerSynchronizationError:LocalizedError {
    case sourceMarker,differentRecordings,retimed
    public var errorDescription:String?{switch self{
    case .sourceMarker:"Choose two clip markers within their original recordings."
    case .differentRecordings:"Choose markers from different recordings."
    case .retimed:"Set camera speeds to 1× before synchronization."
    }}
}
public enum MarkerSynchronization {
    /// Align the leading edges of source-anchored markers. Hidden source markers
    /// remain valid; timing uses the chosen reference clip's actual placement.
    public static func alignment(referenceMarkerID:UUID,targetMarkerID:UUID,in document:ProjectDocument)throws->MarkerAlignment {
        try document.validate()
        let clips=document.sequence.tracks.flatMap(\.clips)
        func source(_ id:UUID)throws->(Marker,Clip,MediaAsset){
            guard let marker=document.sequence.markers.first(where:{$0.id==id}),
                  let clip=clips.first(where:{$0.id==marker.clipID}),
                  let asset=document.assets.first(where:{$0.id==clip.assetID}),asset.kind != .image,
                  marker.time >= .zero,marker.time<asset.duration else{throw MarkerSynchronizationError.sourceMarker}
            guard clip.speed==1,clip.freezeFrame==nil else{throw MarkerSynchronizationError.retimed}
            return (marker,clip,asset)
        }
        let (reference,referenceClip,referenceAsset)=try source(referenceMarkerID)
        let (target,_,targetAsset)=try source(targetMarkerID)
        guard referenceAsset.id != targetAsset.id else{throw MarkerSynchronizationError.differentRecordings}
        guard let first=clips.filter({$0.assetID==referenceAsset.id}).min(by:{$0.start<$1.start}),first.speed==1,first.freezeFrame==nil else{throw MarkerSynchronizationError.retimed}
        let eventTime=try referenceClip.start.checkedAdding(reference.time.checkedSubtracting(referenceClip.sourceStart))
        let referenceOrigin=try first.start.checkedSubtracting(first.sourceStart)
        let offset=try eventTime.checkedSubtracting(target.time).checkedSubtracting(referenceOrigin)
        return .init(referenceAssetID:referenceAsset.id,targetAssetID:targetAsset.id,offset:offset)
    }
}
