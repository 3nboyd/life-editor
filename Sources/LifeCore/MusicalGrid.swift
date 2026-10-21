import Foundation

public struct BeatAnchor: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID; public var time: RationalTime; public var beatIndex: Int64
    public init(id: UUID = UUID(), time: RationalTime, beatIndex: Int64) { self.id=id; self.time=time; self.beatIndex=beatIndex }
}
public struct MusicalDivision: Equatable, Sendable {
    public let time: RationalTime; public let beatIndex: Int64; public let subdivisionIndex: Int; public let isBar: Bool
    public init(time: RationalTime, beatIndex: Int64, subdivisionIndex: Int, isBar: Bool) { self.time=time; self.beatIndex=beatIndex; self.subdivisionIndex=subdivisionIndex; self.isBar=isBar }
}
extension MusicalGrid {
    public var isValid: Bool {
        guard bpm.isFinite, (20...400).contains(bpm), (1...32).contains(beatsPerBar), (1...16).contains(subdivision),
              validGridTime(offset), [1,2,4,8,16,32].contains(beatUnit ?? 4), (swing ?? 0).isFinite, (0...1).contains(swing ?? 0) else { return false }
        let anchors=anchors ?? []
        guard anchors.count <= 10000, Set(anchors.map(\.id)).count == anchors.count,
              anchors.allSatisfy({ validGridTime($0.time) && (-1_000_000_000...1_000_000_000).contains($0.beatIndex) }) else { return false }
        return zip(anchors,anchors.dropFirst()).allSatisfy { $0.time < $1.time && $0.beatIndex < $1.beatIndex }
    }
    /// BPM denotes quarter notes; beatUnit controls the time-signature denominator.
    /// Anchors are absolute timeline points. Outside them, the entered BPM continues without a discontinuity.
    public func divisions(from lower: RationalTime, to upper: RationalTime, maximumCount: Int = 10000) -> [MusicalDivision] {
        guard isValid, validGridTime(lower), validGridTime(upper), upper >= lower, maximumCount > 0,
              let first=try? beat(at:lower), let last=try? beat(at:upper),
              abs(first.seconds) <= 1_000_000_001, abs(last.seconds) <= 1_000_000_001 else { return [] }
        let count=min(maximumCount,100000)
        let initial=Int64(floor(first.seconds*Double(subdivision)))-2
        let final=Int64(ceil(last.seconds*Double(subdivision)))+2
        var result:[MusicalDivision]=[]
        var ordinal=initial
        while ordinal <= final && result.count < count {
            let beatIndex=floorDivision(ordinal,by:Int64(subdivision)), index=Int(ordinal-beatIndex*Int64(subdivision))
            var position=RationalTime(value:ordinal,timescale:Int64(subdivision))
            // Swing delays odd subdivisions up to one third of a subdivision interval.
            if index % 2 == 1 { position=position+RationalTime(value:Int64(((swing ?? 0)*1_000_000).rounded()),timescale:Int64(3*subdivision)*1_000_000) }
            if let time=try? time(at:position), time >= lower && time <= upper {
                result.append(MusicalDivision(time:time,beatIndex:beatIndex,subdivisionIndex:index,isBar:index == 0 && beatIndex % Int64(beatsPerBar) == 0))
            }
            ordinal += 1
        }
        return result
    }
    public func nearestDivision(to time: RationalTime) -> MusicalDivision? {
        guard isValid, let coordinate=try? beat(at:time), abs(coordinate.seconds) <= 1_000_000_000 else { return nil }
        // A local beat neighborhood bounds work even for very dense manually anchored grids.
        let base=Int64(floor(coordinate.seconds))
        guard let lower=try? self.time(at:RationalTime(value:base-1,timescale:1)),
              let upper=try? self.time(at:RationalTime(value:base+2,timescale:1)) else { return nil }
        return divisions(from:max(lower,RationalTime(value:-86400,timescale:1)),to:min(upper,RationalTime(value:86400,timescale:1)),maximumCount:64).min { abs($0.time.seconds-time.seconds) < abs($1.time.seconds-time.seconds) }
    }
    /// Moves annotations only. Recordings and clip timings never participate in a grid shift.
    public func moved(by delta: RationalTime) throws -> MusicalGrid {
        var result=self; result.offset=try offset.checkedAdding(delta)
        if result.anchors != nil { for i in result.anchors!.indices { result.anchors![i].time=try result.anchors![i].time.checkedAdding(delta) } }
        guard result.isValid else { throw DocumentError.invalidTiming }; return result
    }
    private var beatDuration: RationalTime { RationalTime(value:60_000_000,timescale:Int64((bpm*1_000_000).rounded())).scaled(by:4,over:Int64(beatUnit ?? 4)) }
    private func time(at beat: RationalTime) throws -> RationalTime {
        let anchors=anchors ?? []
        if let first=anchors.first, beat <= RationalTime(value:first.beatIndex,timescale:1) {
            return try first.time.checkedAdding(beat.checkedSubtracting(RationalTime(value:first.beatIndex,timescale:1)).checkedScaled(by:beatDuration.value,over:beatDuration.timescale))
        }
        let index=firstAnchor(in:anchors) { RationalTime(value:$0.beatIndex,timescale:1) >= beat }
        if let index, index > 0 {
            let left=anchors[index-1], right=anchors[index]
            let relative=try beat.checkedSubtracting(RationalTime(value:left.beatIndex,timescale:1))
            let span=try right.time.checkedSubtracting(left.time)
            return try left.time.checkedAdding(relative.checkedScaled(by:span.value,over:span.timescale).checkedScaled(by:1,over:right.beatIndex-left.beatIndex))
        }
        let reference=anchors.last
        return try (reference?.time ?? offset).checkedAdding(beat.checkedSubtracting(RationalTime(value:reference?.beatIndex ?? 0,timescale:1)).checkedScaled(by:beatDuration.value,over:beatDuration.timescale))
    }
    private func beat(at time: RationalTime) throws -> RationalTime {
        let anchors=anchors ?? []
        if let first=anchors.first, time <= first.time {
            return try RationalTime(value:first.beatIndex,timescale:1).checkedAdding(time.checkedSubtracting(first.time).checkedScaled(by:beatDuration.timescale,over:beatDuration.value))
        }
        let index=firstAnchor(in:anchors) { $0.time >= time }
        if let index, index > 0 {
            let left=anchors[index-1], right=anchors[index]
            let span=try right.time.checkedSubtracting(left.time)
            return try RationalTime(value:left.beatIndex,timescale:1).checkedAdding(time.checkedSubtracting(left.time).checkedScaled(by:span.timescale,over:span.value).checkedScaled(by:right.beatIndex-left.beatIndex))
        }
        let reference=anchors.last
        return try RationalTime(value:reference?.beatIndex ?? 0,timescale:1).checkedAdding(time.checkedSubtracting(reference?.time ?? offset).checkedScaled(by:beatDuration.timescale,over:beatDuration.value))
    }
    private func firstAnchor(in anchors: [BeatAnchor], predicate: (BeatAnchor) -> Bool) -> Int? {
        var low=0, high=anchors.count
        while low < high { let middle=(low+high)/2; if predicate(anchors[middle]) { high=middle } else { low=middle+1 } }
        return low < anchors.count ? low : nil
    }
    private func floorDivision(_ value: Int64, by divisor: Int64) -> Int64 { value >= 0 ? value/divisor : (value-divisor+1)/divisor }
    private func validGridTime(_ time: RationalTime) -> Bool { time.timescale <= 1_000_000_000 && time.seconds.isFinite && abs(time.seconds) <= 86400 }
}
public struct MarkerRange: Equatable, Sendable {
    public let start: RationalTime; public let duration: RationalTime
    public var end: RationalTime { start+duration }
    public init(start: RationalTime, duration: RationalTime) { self.start=start; self.duration=duration }
}
public enum MarkerResolver {
    public static func sequenceRange(_ marker: Marker, in document: ProjectDocument) -> MarkerRange? {
        guard let id=marker.clipID else { return MarkerRange(start:marker.time,duration:marker.duration) }
        guard let clip=document.sequence.tracks.flatMap(\.clips).first(where: { $0.id == id }), clip.speed.isFinite, (0.25...4).contains(clip.speed),
              let sourceEnd=try? clip.checkedSourceTime(at:clip.end) else { return nil }
        let start=max(marker.time,clip.sourceStart)
        let sourceDuration:RationalTime
        if marker.duration == .zero {
            guard marker.time >= clip.sourceStart, marker.time < sourceEnd else { return nil }
            sourceDuration = .zero
        } else {
            guard let end=try? marker.time.checkedAdding(marker.duration) else { return nil }
            let clippedEnd=min(end,sourceEnd)
            guard clippedEnd > start, let duration=try? clippedEnd.checkedSubtracting(start) else { return nil }
            sourceDuration=duration
        }
        let rate=Int64((clip.speed*1_000_000).rounded())
        guard let relative=try? start.checkedSubtracting(clip.sourceStart).checkedScaled(by:1_000_000,over:rate),
              let sequenceStart=try? clip.start.checkedAdding(relative), let duration=try? sourceDuration.checkedScaled(by:1_000_000,over:rate) else { return nil }
        return MarkerRange(start:sequenceStart,duration:duration)
    }
}
