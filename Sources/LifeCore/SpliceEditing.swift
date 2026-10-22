import Foundation

public struct PlacementProposal:Sendable {
    public let document:ProjectDocument
    public let affectedTrackIDs:Set<UUID>
    public let insertedClipIDs:Set<UUID>
    public let start:RationalTime
    public let duration:RationalTime
}
public enum SpliceError:LocalizedError {
    case relationships, multicam, unequalTrimWindows
    public var errorDescription:String? {
        switch self {
        case .relationships:return "These linked clips require matching edit ranges on every linked track. Detach them or select matching tracks."
        case .multicam:return "Refine multicam angle decisions before splicing their source recordings."
        case .unequalTrimWindows:return "Ripple trim requires linked and grouped clips with matching start and end points."
        }
    }
}
/// Pure, track-local placement preview. Applying its document commits exactly the
/// displayed IDs as one undoable replacement. Original media is never modified.
public enum SpliceEditing {
    public static func proposal(for command:EditCommand,in document:ProjectDocument) throws -> PlacementProposal {
        try document.validate()
        switch command {
        case .insertCopies(let ids,let at):return try copies(ids,at:at,in:document,insert:true)
        case .overwriteCopies(let ids,let at):return try copies(ids,at:at,in:document,insert:false)
        case .rippleTrim(let id,let start,let end):return try rippleTrim(id,start:start,end:end,in:document)
        default:throw DocumentError.invalidTiming
        }
    }
    private static func expanded(_ selected:Set<UUID>,in document:ProjectDocument)throws->Set<UUID> {
        let clips=document.sequence.tracks.flatMap(\.clips)
        guard !selected.isEmpty,selected.isSubset(of:Set(clips.map(\.id))) else {throw DocumentError.clipNotFound}
        var ids=selected
        while true {
            let members=clips.filter{ids.contains($0.id)}
            let links=Set(members.compactMap(\.linkID)),groups=Set(members.compactMap(\.groupID))
            let old=ids
            for clip in clips where clip.linkID.map(links.contains)==true || clip.groupID.map(groups.contains)==true {ids.insert(clip.id)}
            if ids==old {return ids}
        }
    }
    private struct Window:Equatable {let start:RationalTime;let end:RationalTime}
    private static func windows(_ ranges:[Window])->[Window] {
        var result:[Window]=[]
        for range in ranges.sorted(by:{$0.start<$1.start}) {
            if let last=result.last,last.end>=range.start {result[result.count-1]=Window(start:last.start,end:max(last.end,range.end))}
            else {result.append(range)}
        }
        return result
    }
    private static func fragment(_ prior:Clip,from start:RationalTime,to end:RationalTime,at destination:RationalTime,id:UUID,in document:ProjectDocument)throws->Clip {
        guard end>start,start>=prior.start,end<=prior.end else {throw DocumentError.invalidTiming}
        var result=prior;result.id=id;result.start=destination;result.duration=try end.checkedSubtracting(start)
        let offset=try start.checkedSubtracting(prior.start)
        result.sourceStart=try prior.checkedSourceTime(at:start)
        if document.assets.first(where:{$0.id==prior.assetID})?.kind == .image {result.sourceStart = .zero}
        result.volume.evaluationOffset=try prior.volume.evaluationOffset.checkedAdding(offset)
        result.opacity.evaluationOffset=try prior.opacity.evaluationOffset.checkedAdding(offset)
        if let animation=prior.title?.animation {result.title?.animation=try animation.windowed(by:offset)}
        return result
    }
    private static func guardMulticam(_ clips:[Clip],in document:ProjectDocument)throws {
        let assets=Set(document.sequence.multicamGroups.flatMap{$0.angleAssetIDs+($0.audioAssetIDs ?? [])+[$0.masterAudioAssetID].compactMap{$0}})
        if clips.contains(where:{$0.assetID.map(assets.contains)==true}) {throw SpliceError.multicam}
    }
    private static func guardRelationships(_ ranges:[UUID:[Window]],changed:Set<UUID>,in document:ProjectDocument)throws {
        let tracks=document.sequence.tracks
        let clips=tracks.flatMap{track in track.clips.map{(track.id,$0)}}
        for (_,clip) in clips where changed.contains(clip.id) {
            if let link=clip.linkID {
                guard clips.filter({$0.1.linkID==link}).allSatisfy({$0.1.start==clip.start && $0.1.end==clip.end && $0.1.speed==clip.speed}) else {throw SpliceError.relationships}
            }
            let related=try expanded([clip.id],in:document)
            let members=clips.filter{related.contains($0.1.id)}
            guard let first=members.first,let expected=ranges[first.0],members.allSatisfy({ranges[$0.0]==expected}) else {throw SpliceError.relationships}
        }
    }
    private static func copyMarkers(from prior:Clip,to fragments:[Clip],in document:ProjectDocument)throws->[Marker] {
        var result:[Marker]=[]
        for marker in document.sequence.markers where marker.clipID==prior.id {
            var matches:[Clip]=[]
            let markerEnd=try marker.time.checkedAdding(marker.duration)
            for clip in fragments {
                let end=try clip.checkedSourceTime(at:clip.end)
                if marker.duration == .zero ? (marker.time>=clip.sourceStart && marker.time<end) : (marker.time<end && markerEnd>clip.sourceStart) {matches.append(clip)}
            }
            // Hidden annotations outside the original source window survive trims.
            let priorEnd=try prior.checkedSourceTime(at:prior.end)
            if matches.isEmpty,(marker.time<prior.sourceStart || marker.time>=priorEnd),let first=fragments.first {matches=[first]}
            for (index,clip) in matches.enumerated() {var copy=marker;copy.clipID=clip.id;if index>0 {copy.id=UUID()};result.append(copy)}
        }
        return result
    }
    private static func copies(_ selected:Set<UUID>,at requested:RationalTime,in document:ProjectDocument,insert:Bool)throws->PlacementProposal {
        let ids=try expanded(selected,in:document)
        let originals=document.sequence.tracks.flatMap(\.clips).filter{ids.contains($0.id)}
        try guardMulticam(originals,in:document)
        let affected=Set(document.sequence.tracks.filter{$0.clips.contains{ids.contains($0.id)}}.map(\.id))
        guard let anchor=originals.map(\.start).min(),let originalEnd=originals.map(\.end).max() else {throw DocumentError.clipNotFound}
        let hasVisual=document.sequence.tracks.contains{affected.contains($0.id) && $0.kind != .audio}
        let rate=document.sequence.settings.frameRate
        let delta=hasVisual ? try rate.checkedQuantized(requested.checkedSubtracting(anchor)) : try requested.checkedSubtracting(anchor)
        let start=try anchor.checkedAdding(delta)
        guard start >= .zero else {throw DocumentError.invalidTiming}
        var duration=try originalEnd.checkedSubtracting(anchor)
        if hasVisual {
            let frames=try duration.checkedScaled(by:rate.numerator,over:rate.denominator)
            var count=frames.value/frames.timescale
            if frames.value%frames.timescale != 0 {count=try RationalTime(value:count,timescale:1).checkedAdding(.init(value:1,timescale:1)).value}
            duration=try RationalTime(value:count,timescale:1).checkedScaled(by:rate.denominator,over:rate.numerator)
        }
        var next=document
        var copied:[UUID:Clip]=[:],links:[UUID:UUID]=[:],groups:[UUID:UUID]=[:]
        for prior in originals {
            var copy=prior;copy.id=UUID();copy.start=try prior.start.checkedAdding(delta)
            if let link=copy.linkID {if links[link]==nil {links[link]=UUID()};copy.linkID=links[link]}
            if let group=copy.groupID {if groups[group]==nil {groups[group]=UUID()};copy.groupID=groups[group]}
            copied[prior.id]=copy
        }
        var ranges:[UUID:[Window]]=[:]
        for track in document.sequence.tracks where affected.contains(track.id) {
            guard !track.isLocked else {throw DocumentError.lockedTrack}
            ranges[track.id]=insert ? [Window(start:start,end:try start.checkedAdding(duration))] : windows(track.clips.filter{ids.contains($0.id)}.map{Window(start:copied[$0.id]!.start,end:copied[$0.id]!.end)})
        }
        var changed=Set<UUID>(),fragments:[UUID:[Clip]]=[:],rightLinks:[UUID:UUID]=[:]
        var splitLinks:[String:UUID]=[:]
        for t in next.sequence.tracks.indices where affected.contains(next.sequence.tracks[t].id) {
            let track=next.sequence.tracks[t],holes=ranges[track.id]!
            var output:[Clip]=[]
            for prior in track.clips {
                var pieces:[Clip]=[]
                if insert {
                    if prior.end<=start {pieces=[prior]}
                    else if prior.start>=start {var clip=prior;clip.start=try clip.start.checkedAdding(duration);pieces=[clip]}
                    else {
                        let left=try fragment(prior,from:prior.start,to:start,at:prior.start,id:prior.id,in:document)
                        var right=try fragment(prior,from:start,to:prior.end,at:start.checkedAdding(duration),id:UUID(),in:document)
                        if let link=prior.linkID {if rightLinks[link]==nil {rightLinks[link]=UUID()};right.linkID=rightLinks[link]}
                        pieces=[left,right]
                    }
                } else {
                    var cursor=prior.start
                    for hole in holes where hole.end>prior.start && hole.start<prior.end {
                        if hole.start>cursor {pieces.append(try fragment(prior,from:cursor,to:min(hole.start,prior.end),at:cursor,id:pieces.isEmpty ? prior.id:UUID(),in:document))}
                        cursor=max(cursor,hole.end)
                    }
                    if cursor<prior.end {pieces.append(try fragment(prior,from:cursor,to:prior.end,at:cursor,id:pieces.isEmpty ? prior.id:UUID(),in:document))}
                    if pieces.count>1,let link=prior.linkID {
                        // Shared surviving source windows get shared links across AV partners.
                        for i in 1..<pieces.count {let key="\(link.uuidString)|\(pieces[i].start.value)/\(pieces[i].start.timescale)";if splitLinks[key]==nil {splitLinks[key]=UUID()};pieces[i].linkID=splitLinks[key]}
                    }
                }
                if pieces != [prior] {changed.insert(prior.id)}
                fragments[prior.id]=pieces;output += pieces
            }
            output += track.clips.compactMap{copied[$0.id]}
            next.sequence.tracks[t].clips=output.sorted{$0.start<$1.start}
        }
        try guardMulticam(document.sequence.tracks.flatMap(\.clips).filter{changed.contains($0.id)},in:document)
        try guardRelationships(ranges,changed:changed,in:document)
        next.sequence.markers.removeAll{$0.clipID.map(changed.contains)==true}
        for prior in document.sequence.tracks.flatMap(\.clips) where changed.contains(prior.id) {next.sequence.markers += try copyMarkers(from:prior,to:fragments[prior.id] ?? [],in:document)}
        for prior in originals {for var marker in try copyMarkers(from:prior,to:[copied[prior.id]!],in:document) {marker.id=UUID();next.sequence.markers.append(marker)}}
        if let transitions=document.sequence.transitions {
            for index in transitions.indices {
                let prior=transitions[index]
                if let left=fragments[prior.leftClipID]?.last,let right=fragments[prior.rightClipID]?.first,
                   let oldLeft=document.sequence.tracks.flatMap(\.clips).first(where:{$0.id==prior.leftClipID}),
                   let oldRight=document.sequence.tracks.flatMap(\.clips).first(where:{$0.id==prior.rightClipID}),
                   left.end==right.start,try left.checkedSourceTime(at:left.end)==oldLeft.checkedSourceTime(at:oldLeft.end),right.sourceStart==oldRight.sourceStart {
                    next.sequence.transitions?[index].leftClipID=left.id;next.sequence.transitions?[index].rightClipID=right.id
                }
            }
            for prior in transitions {
                if let left=copied[prior.leftClipID],let right=copied[prior.rightClipID] {var copy=prior;copy.id=UUID();copy.leftClipID=left.id;copy.rightClipID=right.id;next.sequence.transitions?.append(copy)}
            }
        }
        try next.validate()
        return PlacementProposal(document:next,affectedTrackIDs:affected,insertedClipIDs:Set(copied.values.map(\.id)),start:start,duration:duration)
    }
    private static func rippleTrim(_ id:UUID,start requestedStart:RationalTime,end requestedEnd:RationalTime,in document:ProjectDocument)throws->PlacementProposal {
        let ids=try expanded([id],in:document)
        let clips=document.sequence.tracks.flatMap(\.clips)
        guard let original=clips.first(where:{$0.id==id}) else {throw DocumentError.clipNotFound}
        guard clips.filter({ids.contains($0.id)}).allSatisfy({$0.start==original.start && $0.end==original.end}) else {throw SpliceError.unequalTrimWindows}
        let affected=Set(document.sequence.tracks.filter{$0.clips.contains{ids.contains($0.id)}}.map(\.id))
        let visual=document.sequence.tracks.contains{affected.contains($0.id) && $0.kind != .audio}
        let start=visual ? try document.sequence.settings.frameRate.checkedQuantized(requestedStart):requestedStart
        let end=visual ? try document.sequence.settings.frameRate.checkedQuantized(requestedEnd):requestedEnd
        guard end>start else {throw DocumentError.invalidTiming}
        let duration=try end.checkedSubtracting(start),delta=try duration.checkedSubtracting(original.duration)
        var next=document,changed=Set<UUID>()
        var ranges:[UUID:[Window]]=[:]
        for t in next.sequence.tracks.indices where affected.contains(next.sequence.tracks[t].id) {
            guard !next.sequence.tracks[t].isLocked else {throw DocumentError.lockedTrack}
            ranges[next.sequence.tracks[t].id]=[Window(start:original.start,end:original.end)]
            for c in next.sequence.tracks[t].clips.indices {
                let prior=next.sequence.tracks[t].clips[c]
                if ids.contains(prior.id) {
                    var clip=prior;clip.duration=duration
                    let offset=try start.checkedSubtracting(prior.start)
                    clip.sourceStart=try prior.checkedSourceTime(at:start)
                    if document.assets.first(where:{$0.id==prior.assetID})?.kind == .image || prior.assetID == nil {clip.sourceStart=max(.zero,clip.sourceStart)}
                    guard clip.sourceStart >= .zero else {throw DocumentError.sourceBoundary}
                    clip.volume.evaluationOffset=try prior.volume.evaluationOffset.checkedAdding(offset)
                    clip.opacity.evaluationOffset=try prior.opacity.evaluationOffset.checkedAdding(offset)
                    if let animation=prior.title?.animation {clip.title?.animation=try animation.windowed(by:offset)}
                    next.sequence.tracks[t].clips[c]=clip;changed.insert(prior.id)
                } else if prior.start>=original.end {
                    next.sequence.tracks[t].clips[c].start=try prior.start.checkedAdding(delta);changed.insert(prior.id)
                }
            }
        }
        try guardRelationships(ranges,changed:changed,in:document)
        try guardMulticam(clips.filter{changed.contains($0.id)},in:document)
        try next.validate()
        return PlacementProposal(document:next,affectedTrackIDs:affected,insertedClipIDs:[],start:original.start,duration:duration)
    }
}
