import Foundation

public enum AdjustmentLayerError:Error,LocalizedError,Equatable {
    case invalidContents,invalidTransition
    public var errorDescription:String?{
        switch self{
        case .invalidContents:return "Use effects and opacity only on adjustment layers."
        case .invalidTransition:return "Use opacity fades on adjustment layers instead of video transitions."
        }
    }
}
public enum AdjustmentLayers {
    public static func validate(_ clip:Clip)throws{
        guard clip.assetID == nil,clip.title == nil,clip.graphic == nil,clip.freezeFrame == nil,clip.visual == nil,clip.audio == nil,clip.audioEnabled != true,clip.linkID == nil,clip.speed==1,
              clip.volume.baseValue==1,clip.volume.points.isEmpty else{throw AdjustmentLayerError.invalidContents}
    }
    public static func validate(in document:ProjectDocument)throws{
        let tracks=document.sequence.tracks.filter{$0.kind == .adjustment}
        for track in tracks{for clip in track.clips{try validate(clip)}}
        let ids=Set(tracks.flatMap(\.clips).map(\.id))
        guard !(document.sequence.transitions ?? []).contains(where:{$0.isEnabled && (ids.contains($0.leftClipID) || ids.contains($0.rightClipID))}) else{throw AdjustmentLayerError.invalidTransition}
    }
    /// The layer is appended at the top; its existing sourceStart records the effects animation clock.
    public static func adding(at time:RationalTime,duration:RationalTime,in document:ProjectDocument)throws->ProjectDocument{
        try document.validate();try validate(in:document);guard time >= .zero,duration > .zero else{throw DocumentError.invalidTiming}
        let start=try document.sequence.settings.frameRate.checkedQuantized(time),length=try document.sequence.settings.frameRate.checkedQuantized(duration)
        guard length > .zero else{throw DocumentError.invalidTiming}
        let clip=Clip(name:"Adjust",start:start,duration:length,effects:[],audioEnabled:false)
        try validate(clip);var result=document
        result.sequence.tracks.append(Track(name:"Adjust",kind:.adjustment,clips:[clip]));try result.validate();return result
    }
}
