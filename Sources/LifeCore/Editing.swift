import Foundation

public enum EditCommand: Sendable {
    case replace(ProjectDocument)
    case insertCopies(clipIDs:Set<UUID>,at:RationalTime)
    case overwriteCopies(clipIDs:Set<UUID>,at:RationalTime)
    case rippleTrim(clipID:UUID,start:RationalTime,end:RationalTime)
    case split(clipID: UUID, at: RationalTime)
    case move(clipID: UUID, to: RationalTime)
    case trim(clipID: UUID, start: RationalTime, end: RationalTime)
    /// Independent clip retiming; other clips retain their position, speed, and duration.
    case retime(clipID: UUID, speed: Double, preservesPitch: Bool)
    case remove(clipID: UUID)
    case duplicate(clipID: UUID, to: RationalTime)
    /// Closes the deleted clip's time interval on every unlocked track.
    case rippleDelete(clipID: UUID)
    case renameTrack(trackID: UUID, name: String)
    case reorderTrack(trackID: UUID, to: Int)
    case removeTrack(trackID: UUID)
    case convertMarkerToTitle(id: UUID)
    case addTransition(leftClipID: UUID, rightClipID: UUID, kind: TransitionKind, duration: RationalTime)
    case setTransitionDuration(id: UUID, duration: RationalTime)
    case removeTransition(id: UUID)
    case moveMany(clipIDs: Set<UUID>, delta: RationalTime)
    case removeMany(clipIDs: Set<UUID>)
    case group(clipIDs: Set<UUID>)
    case ungroup(clipIDs: Set<UUID>)
    case detach(clipIDs: Set<UUID>)
    case link(clipIDs: Set<UUID>)
    /// Shift source content, preserving sequence boundaries and clip-local automation.
    case slip(clipID: UUID, by: RationalTime)
    /// Move the common boundary of adjacent clips, preserving their outside boundaries.
    case roll(leftClipID: UUID, rightClipID: UUID, to: RationalTime)
}

/// Every operation builds and validates a candidate before replacing authoritative state.
@MainActor public final class ProjectEditor {
    public private(set) var document: ProjectDocument
    private var undoStack: [ProjectDocument] = []
    private var redoStack: [ProjectDocument] = []
    private var groupStart: ProjectDocument?
    private var groupDepth = 0
    public init(document: ProjectDocument = .init()) { self.document=document }
    public var canUndo: Bool { groupDepth == 0 && !undoStack.isEmpty }
    public var canRedo: Bool { groupDepth == 0 && !redoStack.isEmpty }
    public var snapshot: ProjectSnapshot { .init(document: document) }
    public func beginUndoGroup() {
        if groupDepth == 0 { groupStart=document }
        groupDepth += 1
    }
    public func endUndoGroup() {
        guard groupDepth > 0 else { return }
        groupDepth -= 1
        if groupDepth == 0 {
            if let initial=groupStart, initial != document { undoStack.append(initial); redoStack.removeAll() }
            groupStart=nil
        }
    }
    public func undo() { guard groupDepth == 0, let prior=undoStack.popLast() else { return }; redoStack.append(document); document=prior }
    public func redo() { guard groupDepth == 0, let next=redoStack.popLast() else { return }; undoStack.append(document); document=next }
    public func perform(_ command: EditCommand) throws {
        var next=document
        switch command {
        case .replace(let replacement): next=replacement
        case .insertCopies,.overwriteCopies,.rippleTrim:next=try SpliceEditing.proposal(for:command,in:document).document
        case .move(let id, let time):
            let original=try find(id)
            let time=editTime(time,for:original)
            let delta=try time.checkedSubtracting(original.start)
            for t in next.sequence.tracks.indices {
                for c in next.sequence.tracks[t].clips.indices where linked(next.sequence.tracks[t].clips[c], to: original) {
                    guard !next.sequence.tracks[t].isLocked else { throw DocumentError.lockedTrack }
                    next.sequence.tracks[t].clips[c].start = try next.sequence.tracks[t].clips[c].start.checkedAdding(delta)
                    try checkPlacement(next.sequence.tracks[t], clipID: next.sequence.tracks[t].clips[c].id)
                }
            }
        case .trim(let id, let start, let end):
            let original=try find(id)
            let start=editTime(start,for:original), end=editTime(end,for:original)
            guard end > start else { throw DocumentError.invalidTiming }
            let startDelta=try start.checkedSubtracting(original.start), endDelta=try end.checkedSubtracting(original.end)
            for t in next.sequence.tracks.indices {
                for c in next.sequence.tracks[t].clips.indices where linked(next.sequence.tracks[t].clips[c], to: original) {
                    guard !next.sequence.tracks[t].isLocked else { throw DocumentError.lockedTrack }
                    var clip=next.sequence.tracks[t].clips[c]
                    let prior=clip
                    clip.start = try clip.start.checkedAdding(startDelta)
                    clip.duration = try clip.duration.checkedAdding(endDelta.checkedSubtracting(startDelta))
                    clip.sourceStart=try prior.checkedSourceTime(at:prior.start.checkedAdding(startDelta))
                    if next.assets.first(where: { $0.id == clip.assetID })?.kind == .image { clip.sourceStart = .zero }
                    guard clip.sourceStart >= .zero else { throw DocumentError.sourceBoundary }
                    if let asset=next.assets.first(where: { $0.id == clip.assetID }), asset.kind != .image, try clip.checkedSourceTime(at: clip.end) > asset.duration { throw DocumentError.sourceBoundary }
                    clip.volume=try prior.volume.window(from: startDelta, duration: clip.duration)
                    clip.opacity=try prior.opacity.window(from: startDelta, duration: clip.duration)
                    if let animation=prior.title?.animation { clip.title?.animation=try animation.windowed(by:startDelta) }
                    next.sequence.tracks[t].clips[c]=clip
                    try checkPlacement(next.sequence.tracks[t], clipID: clip.id)
                }
            }
        case .split(let id, let time):
            let original=try find(id)
            let time=editTime(time,for:original)
            guard time > original.start && time < original.end else { throw DocumentError.invalidSplit }
            let rightLink=original.linkID == nil ? nil : UUID()
            for t in next.sequence.tracks.indices {
                let ids=next.sequence.tracks[t].clips.filter { linked($0,to:original) }.map(\.id)
                for clipID in ids {
                    guard !next.sequence.tracks[t].isLocked else { throw DocumentError.lockedTrack }
                    let index=next.sequence.tracks[t].clips.firstIndex { $0.id == clipID }!
                    let prior=next.sequence.tracks[t].clips[index]
                    guard time > prior.start && time < prior.end else { throw DocumentError.invalidSplit }
                    var left=prior, right=prior
                    left.duration=try time.checkedSubtracting(prior.start)
                    right.id=UUID(); right.start=time; right.duration=try prior.end.checkedSubtracting(time); right.sourceStart=try prior.checkedSourceTime(at:time); right.linkID=rightLink
                    left.volume=try prior.volume.window(from:.zero,duration:left.duration); left.opacity=try prior.opacity.window(from:.zero,duration:left.duration)
                    right.volume=try prior.volume.window(from:left.duration,duration:right.duration); right.opacity=try prior.opacity.window(from:left.duration,duration:right.duration)
                    if let animation=prior.title?.animation { right.title?.animation=try animation.windowed(by:left.duration) }
                    next.sequence.tracks[t].clips[index]=left
                    next.sequence.tracks[t].clips.insert(right,at:index+1)
                    // Range markers crossing the split remain attached to both source windows.
                    let crossing=next.sequence.markers.filter { marker in
                        marker.clipID == prior.id && marker.duration > .zero && marker.time < right.sourceStart &&
                        (try? marker.time.checkedAdding(marker.duration)).map { $0 > right.sourceStart } == true
                    }
                    for var marker in crossing { marker.id=UUID(); marker.clipID=right.id; next.sequence.markers.append(marker) }
                    // Clip markers use source time, so move markers whose source content is now in the right segment.
                    for m in next.sequence.markers.indices where next.sequence.markers[m].clipID == prior.id && next.sequence.markers[m].time >= right.sourceStart { next.sequence.markers[m].clipID=right.id }
                }
            }
        case .retime(let id, let speed, let preservesPitch):
            guard speed.isFinite, (0.25...4).contains(speed) else { throw DocumentError.invalidTiming }
            _ = try find(id)
            let newRate=Int64((speed*1_000_000).rounded())
            for t in next.sequence.tracks.indices {
                guard let c=next.sequence.tracks[t].clips.firstIndex(where: { $0.id == id }) else { continue }
                guard !next.sequence.tracks[t].isLocked else { throw DocumentError.lockedTrack }
                var clip=next.sequence.tracks[t].clips[c]
                let oldRate=Int64((clip.speed*1_000_000).rounded())
                clip.duration=try clip.duration.checkedScaled(by:oldRate,over:newRate)
                clip.volume=try clip.volume.retimed(by:oldRate,over:newRate)
                clip.opacity=try clip.opacity.retimed(by:oldRate,over:newRate)
                if let animation=clip.title?.animation { clip.title?.animation=try animation.retimed(by:newRate,over:oldRate) }
                // Store the exact rate represented by the document's micro-rational mapping.
                clip.speed=Double(newRate)/1_000_000
                clip.preservesPitch=preservesPitch
                next.sequence.tracks[t].clips[c]=clip
            }
        case .convertMarkerToTitle(let id):
            guard let marker=next.sequence.markers.first(where: { $0.id == id }), let range=MarkerResolver.sequenceRange(marker,in:next) else { throw DocumentError.clipNotFound }
            let duration=range.duration > .zero ? range.duration : RationalTime(value:3,timescale:1)
            let text=marker.name.isEmpty ? (marker.note.isEmpty ? "Marker" : marker.note) : marker.name
            let title=Clip(name:text,start:range.start,duration:duration,title:TitleContent(text:text))
            next.sequence.tracks.append(Track(name:"Title",kind:.title,clips:[title]))
        case .addTransition(let leftID, let rightID, let kind, let requested):
            let (track,_,_)=try TransitionResolver.pair(leftID,rightID,in:document)
            guard !track.isLocked else { throw DocumentError.lockedTrack }
            let duration=document.sequence.settings.frameRate.quantized(requested)
            guard duration > .zero else { throw DocumentError.invalidTiming }
            let maximum=try TransitionResolver.availableDuration(leftClipID:leftID,rightClipID:rightID,in:document)
            guard duration <= maximum else { throw DocumentError.sourceBoundary }
            var transitions=next.sequence.transitions ?? []
            transitions.append(VideoTransition(kind:kind,trackID:track.id,leftClipID:leftID,rightClipID:rightID,duration:duration))
            next.sequence.transitions=transitions
        case .setTransitionDuration(let id, let requested):
            guard let i=next.sequence.transitions?.firstIndex(where: { $0.id == id }), let prior=next.sequence.transitions?[i] else { throw DocumentError.clipNotFound }
            guard let track=next.sequence.tracks.first(where: { $0.id == prior.trackID }) else { throw DocumentError.trackNotFound }
            guard !track.isLocked else { throw DocumentError.lockedTrack }
            let duration=document.sequence.settings.frameRate.quantized(requested)
            guard duration > .zero else { throw DocumentError.invalidTiming }
            let maximum=try TransitionResolver.availableDuration(leftClipID:prior.leftClipID,rightClipID:prior.rightClipID,in:document,excluding:id)
            guard duration <= maximum else { throw DocumentError.sourceBoundary }
            next.sequence.transitions?[i].duration=duration
        case .removeTransition(let id):
            guard let transition=next.sequence.transitions?.first(where: { $0.id == id }) else { throw DocumentError.clipNotFound }
            if next.sequence.tracks.first(where: { $0.id == transition.trackID })?.isLocked == true { throw DocumentError.lockedTrack }
            next.sequence.transitions?.removeAll { $0.id == id }
        case .moveMany(let selected, let requestedDelta):
            let ids=try expanded(selected)
            let hasVisual=document.sequence.tracks.contains { $0.kind != .audio && $0.clips.contains { ids.contains($0.id) } }
            let delta=hasVisual ? document.sequence.settings.frameRate.quantized(requestedDelta) : requestedDelta
            for t in next.sequence.tracks.indices {
                guard !next.sequence.tracks[t].isLocked || !next.sequence.tracks[t].clips.contains(where: { ids.contains($0.id) }) else { throw DocumentError.lockedTrack }
                for c in next.sequence.tracks[t].clips.indices where ids.contains(next.sequence.tracks[t].clips[c].id) {
                    next.sequence.tracks[t].clips[c].start=try next.sequence.tracks[t].clips[c].start.checkedAdding(delta)
                }
            }
        case .removeMany(let selected):
            let ids=try expanded(selected)
            for t in next.sequence.tracks.indices {
                guard !next.sequence.tracks[t].isLocked || !next.sequence.tracks[t].clips.contains(where: { ids.contains($0.id) }) else { throw DocumentError.lockedTrack }
                next.sequence.tracks[t].clips.removeAll { ids.contains($0.id) }
            }
            next.sequence.markers.removeAll { $0.clipID.map(ids.contains) ?? false }
        case .group(let selected):
            let ids=try expanded(selected)
            guard ids.count >= 2 else { throw DocumentError.invalidTiming }
            let group=UUID()
            try update(&next,ids:ids) { $0.groupID=group }
        case .ungroup(let selected):
            let ids=try expanded(selected,links:false,groups:true)
            try update(&next,ids:ids) { $0.groupID=nil }
        case .detach(let selected):
            let ids=try expanded(selected,links:true,groups:false)
            try update(&next,ids:ids) { $0.linkID=nil }
        case .link(let selected):
            let ids=try expanded(selected,links:true,groups:false)
            let clips=document.sequence.tracks.flatMap(\.clips).filter { ids.contains($0.id) }
            guard let first=clips.first, clips.count >= 2,
                  clips.allSatisfy({ $0.start == first.start && $0.duration == first.duration && $0.speed == first.speed }) else { throw DocumentError.invalidTiming }
            let link=UUID()
            try update(&next,ids:ids) { $0.linkID=link }
        case .slip(let id, let requestedDelta):
            let original=try find(id), delta=editTime(requestedDelta,for:try find(id))
            let ids=try expanded([original.id],links:true,groups:false)
            try update(&next,ids:ids) { clip in
                clip.sourceStart=try clip.sourceStart.checkedAdding(delta)
                if document.assets.first(where: { $0.id == clip.assetID })?.kind == .image { clip.sourceStart = .zero }
                guard clip.sourceStart >= .zero else { throw DocumentError.sourceBoundary }
            }
        case .roll(let leftID, let rightID, let requestedBoundary):
            let originalLeft=try find(leftID), originalRight=try find(rightID)
            guard originalLeft.end == originalRight.start else { throw DocumentError.invalidSplit }
            let boundary=editTime(requestedBoundary,for:originalLeft)
            let leftIDs=try expanded([leftID],links:true,groups:false), rightIDs=try expanded([rightID],links:true,groups:false)
            guard leftIDs.isDisjoint(with:rightIDs) else { throw DocumentError.invalidSplit }
            for t in next.sequence.tracks.indices {
                let leftIndex=next.sequence.tracks[t].clips.firstIndex { leftIDs.contains($0.id) }
                let rightIndex=next.sequence.tracks[t].clips.firstIndex { rightIDs.contains($0.id) }
                if leftIndex == nil && rightIndex == nil { continue }
                guard let l=leftIndex, let r=rightIndex else { throw DocumentError.invalidSplit }
                guard !next.sequence.tracks[t].isLocked else { throw DocumentError.lockedTrack }
                let left=next.sequence.tracks[t].clips[l], right=next.sequence.tracks[t].clips[r]
                guard left.end == right.start, boundary > left.start, boundary < right.end else { throw DocumentError.invalidSplit }
                var newLeft=left, newRight=right
                newLeft.duration=try boundary.checkedSubtracting(left.start)
                newRight.start=boundary; newRight.duration=try right.end.checkedSubtracting(boundary)
                newRight.sourceStart=try right.checkedSourceTime(at:boundary)
                if document.assets.first(where: { $0.id == newRight.assetID })?.kind == .image { newRight.sourceStart = .zero }
                guard newRight.sourceStart >= .zero else { throw DocumentError.sourceBoundary }
                let delta=try boundary.checkedSubtracting(right.start)
                newRight.volume=try right.volume.window(from:delta,duration:newRight.duration)
                newRight.opacity=try right.opacity.window(from:delta,duration:newRight.duration)
                if let animation=right.title?.animation { newRight.title?.animation=try animation.windowed(by:delta) }
                next.sequence.tracks[t].clips[l]=newLeft; next.sequence.tracks[t].clips[r]=newRight
            }
        case .renameTrack(let id, let name):
            guard let t=next.sequence.tracks.firstIndex(where: { $0.id == id }) else { throw DocumentError.trackNotFound }
            guard !next.sequence.tracks[t].isLocked else { throw DocumentError.lockedTrack }
            next.sequence.tracks[t].name=name
        case .reorderTrack(let id, let destination):
            guard let t=next.sequence.tracks.firstIndex(where: { $0.id == id }) else { throw DocumentError.trackNotFound }
            guard !next.sequence.tracks[t].isLocked else { throw DocumentError.lockedTrack }
            guard next.sequence.tracks.indices.contains(destination) else { throw DocumentError.trackNotFound }
            let track=next.sequence.tracks.remove(at:t); next.sequence.tracks.insert(track,at:destination)
        case .removeTrack(let id):
            guard let t=next.sequence.tracks.firstIndex(where: { $0.id == id }) else { throw DocumentError.trackNotFound }
            guard !next.sequence.tracks[t].isLocked else { throw DocumentError.lockedTrack }
            let ids=Set(next.sequence.tracks[t].clips.map(\.id))
            next.sequence.tracks.remove(at:t)
            next.sequence.markers.removeAll { $0.clipID.map(ids.contains) ?? false }
        case .duplicate(let id, let time):
            let original=try find(id), target=editTime(time,for:try find(id))
            let delta=try target.checkedSubtracting(original.start), newLink=original.linkID == nil ? nil : UUID()
            let newGroup=original.groupID == nil ? nil : UUID()
            for t in next.sequence.tracks.indices {
                let originals=next.sequence.tracks[t].clips.filter { linked($0,to:original) }
                guard originals.isEmpty || !next.sequence.tracks[t].isLocked else { throw DocumentError.lockedTrack }
                for var copy in originals { copy.id=UUID(); copy.linkID=newLink; copy.groupID=newGroup; copy.start=try copy.start.checkedAdding(delta); next.sequence.tracks[t].clips.append(copy) }
            }
        case .rippleDelete(let id):
            let original=try find(id)
            for t in next.sequence.tracks.indices {
                let affected=next.sequence.tracks[t].clips.contains { linked($0,to:original) || $0.start >= original.end }
                guard !affected || !next.sequence.tracks[t].isLocked else { throw DocumentError.lockedTrack }
                // Crossing clips require a range-edit tool; reject rather than silently desynchronize them.
                guard !next.sequence.tracks[t].clips.contains(where: { !linked($0,to:original) && $0.start < original.end && $0.end > original.start }) else { throw DocumentError.overlap }
                next.sequence.tracks[t].clips.removeAll { linked($0,to:original) }
                for c in next.sequence.tracks[t].clips.indices where next.sequence.tracks[t].clips[c].start >= original.end { next.sequence.tracks[t].clips[c].start=try next.sequence.tracks[t].clips[c].start.checkedSubtracting(original.duration) }
            }
            let remainingIDs=Set(next.sequence.tracks.flatMap(\.clips).map(\.id))
            next.sequence.markers.removeAll { $0.clipID.map { !remainingIDs.contains($0) } ?? false }
            for m in next.sequence.markers.indices where next.sequence.markers[m].clipID == nil && next.sequence.markers[m].time >= original.end { next.sequence.markers[m].time=try next.sequence.markers[m].time.checkedSubtracting(original.duration) }
        case .remove(let id):
            let original=try find(id)
            for t in next.sequence.tracks.indices {
                if next.sequence.tracks[t].clips.contains(where: { linked($0,to:original) }) && next.sequence.tracks[t].isLocked { throw DocumentError.lockedTrack }
                next.sequence.tracks[t].clips.removeAll { linked($0,to:original) }
            }
            let remainingIDs=Set(next.sequence.tracks.flatMap(\.clips).map(\.id))
            next.sequence.markers.removeAll { $0.clipID.map { !remainingIDs.contains($0) } ?? false }
        }
        try next.validate()
        guard next != document else { return }
        if groupDepth == 0 { undoStack.append(document) }; redoStack.removeAll(); document=next
    }
    /// Expand relationships transitively once, avoiding double-deltas when both AV partners are selected.
    private func expanded(_ selected: Set<UUID>, links: Bool = true, groups: Bool = true) throws -> Set<UUID> {
        let clips=document.sequence.tracks.flatMap(\.clips)
        guard selected.isSubset(of:Set(clips.map(\.id))) else { throw DocumentError.clipNotFound }
        var ids=selected
        while true {
            let members=clips.filter { ids.contains($0.id) }
            let linkIDs=Set(members.compactMap(\.linkID)), groupIDs=Set(members.compactMap(\.groupID))
            let prior=ids
            for clip in clips where (links && clip.linkID.map(linkIDs.contains) == true) || (groups && clip.groupID.map(groupIDs.contains) == true) { ids.insert(clip.id) }
            if prior == ids { return ids }
        }
    }
    private func update(_ next: inout ProjectDocument, ids: Set<UUID>, mutation: (inout Clip) throws -> Void) throws {
        for t in next.sequence.tracks.indices {
            guard !next.sequence.tracks[t].isLocked || !next.sequence.tracks[t].clips.contains(where: { ids.contains($0.id) }) else { throw DocumentError.lockedTrack }
            for c in next.sequence.tracks[t].clips.indices where ids.contains(next.sequence.tracks[t].clips[c].id) { try mutation(&next.sequence.tracks[t].clips[c]) }
        }
    }
    private func editTime(_ time: RationalTime, for clip: Clip) -> RationalTime {
        let track=document.sequence.tracks.first { $0.clips.contains(where: { $0.id == clip.id }) }
        return track?.kind == .audio ? time : document.sequence.settings.frameRate.quantized(time)
    }
    private func find(_ id: UUID) throws -> Clip {
        guard let clip=document.sequence.tracks.flatMap(\.clips).first(where: { $0.id == id }) else { throw DocumentError.clipNotFound }; return clip
    }
    private func linked(_ clip: Clip, to original: Clip) -> Bool { clip.id == original.id || (original.linkID != nil && clip.linkID == original.linkID) }
    private func checkPlacement(_ track: Track, clipID: UUID) throws {
        let clip=track.clips.first { $0.id == clipID }!
        guard !track.clips.contains(where: { $0.id != clip.id && clip.start < $0.end && clip.end > $0.start }) else { throw DocumentError.overlap }
    }
}

extension AutomationEnvelope {
    fileprivate func retimed(by numerator: Int64, over denominator: Int64) throws -> Self {
        var result=self
        result.evaluationOffset=try evaluationOffset.checkedScaled(by:numerator,over:denominator)
        for i in result.points.indices {
            result.points[i].time=try points[i].time.checkedScaled(by:numerator,over:denominator)
        }
        return result
    }
    fileprivate func window(from start: RationalTime, duration: RationalTime) throws -> Self {
        var result=self
        result.evaluationOffset = try result.evaluationOffset.checkedAdding(start)
        return result
    }
}
