import Foundation

public enum AssetKind: String, Codable, Sendable { case video, audio, image }
public enum TrackKind: String, Codable, Sendable { case video, audio, image, title, caption, shape, drawing, adjustment }
public struct MediaAsset: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID; public var url: URL; public var kind: AssetKind; public var duration: RationalTime
    /// Required native conversion intermediate; original URL retains provenance.
    public var preparedURL: URL?
    public init(id: UUID = UUID(), url: URL, kind: AssetKind, duration: RationalTime, preparedURL: URL? = nil) { self.id=id; self.url=url; self.kind=kind; self.duration=duration; self.preparedURL=preparedURL }
}
public enum Interpolation: String, Codable, Sendable { case linear, eased, hold }
public struct AutomationPoint: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID; public var time: RationalTime; public var value: Double; public var interpolation: Interpolation
    public init(id: UUID = UUID(), time: RationalTime, value: Double, interpolation: Interpolation = .linear) { self.id=id; self.time=time; self.value=value; self.interpolation=interpolation }
}
/// Base value is linear gain; normalized points multiply that value. Points use clip-local time.
public struct AutomationEnvelope: Codable, Equatable, Sendable {
    public var baseValue: Double; public var points: [AutomationPoint]
    /// Preserves the exact original curve across trims/splits, including eased segments.
    public var evaluationOffset: RationalTime
    public init(baseValue: Double = 1, points: [AutomationPoint] = [], evaluationOffset: RationalTime = .zero) { self.baseValue=baseValue; self.points=points; self.evaluationOffset=evaluationOffset }
    public func value(at localTime: RationalTime) -> Double {
        (try? checkedValue(at:localTime)) ?? baseValue
    }
    public func checkedValue(at localTime: RationalTime) throws -> Double {
        let time = try localTime.checkedAdding(evaluationOffset)
        let sorted = points.sorted { $0.time < $1.time }
        guard let first = sorted.first else { return baseValue }
        if time < first.time { return baseValue * first.value }
        for (left,right) in zip(sorted,sorted.dropFirst()) where time < right.time {
            if left.interpolation == .hold { return baseValue * left.value }
            var fraction = try time.checkedSubtracting(left.time).seconds / right.time.checkedSubtracting(left.time).seconds
            if left.interpolation == .eased { fraction = fraction*fraction*(3-2*fraction) }
            return baseValue * (left.value + (right.value-left.value)*fraction)
        }
        return baseValue * sorted.last!.value
    }
}
public struct TitleContent: Codable, Equatable, Sendable {
    public var text: String; public var fontSize: Double; public var style: TitleStyle?; public var animation: TitleAnimation?
    public init(text: String, fontSize: Double = 64, style: TitleStyle? = nil, animation: TitleAnimation? = nil) { self.text=text; self.fontSize=fontSize; self.style=style; self.animation=animation }
}
public struct Clip: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID; public var name: String; public var assetID: UUID?
    public var start: RationalTime; public var duration: RationalTime; public var sourceStart: RationalTime
    public var speed: Double; public var preservesPitch: Bool; public var audioEnabled:Bool?; public var linkID: UUID?; public var groupID: UUID?
    public var volume: AutomationEnvelope; public var opacity: AutomationEnvelope; public var title: TitleContent?
    public var freezeFrame:FreezeFrameContent?
    public var effects: [EffectInstance]?; public var visual: VisualTransform?; public var graphic: GraphicContent?; public var audio: AudioSettings?
    public init(id: UUID = UUID(), name: String = "Clip", assetID: UUID? = nil, start: RationalTime = .zero, duration: RationalTime, sourceStart: RationalTime = .zero, speed: Double = 1, preservesPitch: Bool = true, linkID: UUID? = nil, volume: AutomationEnvelope = .init(), opacity: AutomationEnvelope = .init(), title: TitleContent? = nil, effects: [EffectInstance]? = nil, visual: VisualTransform? = nil, groupID: UUID? = nil, audioEnabled:Bool? = nil, graphic: GraphicContent? = nil, audio: AudioSettings? = nil, freezeFrame:FreezeFrameContent? = nil) {
        self.id=id; self.name=name; self.assetID=assetID; self.start=start; self.duration=duration; self.sourceStart=sourceStart; self.speed=speed; self.preservesPitch=preservesPitch; self.linkID=linkID; self.volume=volume; self.opacity=opacity; self.title=title; self.effects=effects; self.visual=visual;self.audioEnabled=audioEnabled; self.groupID=groupID; self.graphic=graphic; self.audio=audio;self.freezeFrame=freezeFrame
    }
    public var end: RationalTime { start + duration }
    public func checkedSourceTime(at sequenceTime: RationalTime) throws -> RationalTime {
        if let freezeFrame{return freezeFrame.sourceTime}
        let local=try sequenceTime.checkedSubtracting(start)
        let offset=try local.checkedScaled(by:Int64((speed*1_000_000).rounded()),over:1_000_000)
        return try sourceStart.checkedAdding(offset)
    }
    public func sourceTime(at sequenceTime: RationalTime) -> RationalTime {
        if let freezeFrame{return freezeFrame.sourceTime}
        return sourceStart + (sequenceTime-start).scaled(by: Int64((speed*1_000_000).rounded()), over: 1_000_000)
    }
}
public struct Track: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID; public var name: String; public var kind: TrackKind; public var clips: [Clip]
    public var isMuted: Bool; public var isHidden: Bool; public var isLocked: Bool
    public init(id: UUID = UUID(), name: String, kind: TrackKind, clips: [Clip] = [], isMuted: Bool = false, isHidden: Bool = false, isLocked: Bool = false) { self.id=id; self.name=name; self.kind=kind; self.clips=clips; self.isMuted=isMuted; self.isHidden=isHidden; self.isLocked=isLocked }
}
public struct Marker: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID; public var time: RationalTime; public var duration: RationalTime; public var name: String; public var note: String; public var clipID: UUID?; public var color: RGBAColor?
    public init(id: UUID = UUID(), time: RationalTime, duration: RationalTime = .zero, name: String = "", note: String = "", clipID: UUID? = nil, color: RGBAColor? = nil) { self.id=id; self.time=time; self.duration=duration; self.name=name; self.note=note; self.clipID=clipID; self.color=color }
}
public struct MulticamCut: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID; public var time: RationalTime; public var angleID: UUID
    public init(id: UUID = UUID(), time: RationalTime, angleID: UUID) { self.id=id; self.time=time; self.angleID=angleID }
    private enum CodingKeys:String,CodingKey { case id,time,angleID }
    public init(from decoder:any Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        time=try c.decode(RationalTime.self,forKey:.time);angleID=try c.decode(UUID.self,forKey:.angleID)
        // Stable across repeated legacy reads, without introducing platform APIs.
        let text="\(angleID.uuidString)|\(time.value)/\(time.timescale)"
        var bytes=[UInt8](repeating:0,count:16)
        for lane in 0..<2 { var hash:UInt64=14695981039346656037 ^ UInt64(lane);for byte in text.utf8 {hash=(hash ^ UInt64(byte)) &* 1099511628211};for n in 0..<8 {bytes[lane*8+n]=UInt8(truncatingIfNeeded:hash >> (n*8))} }
        bytes[6]=(bytes[6]&15)|80;bytes[8]=(bytes[8]&63)|128
        id=try c.decodeIfPresent(UUID.self,forKey:.id) ?? UUID(uuid:(bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
}
public struct MulticamGroup: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID; public var angleAssetIDs: [UUID]; public var masterAudioAssetID: UUID?; public var cuts: [MulticamCut]; public var audioAssetIDs:[UUID]?; public var audioCuts:[MulticamCut]?
    public init(id: UUID = UUID(), angleAssetIDs: [UUID], masterAudioAssetID: UUID? = nil, cuts: [MulticamCut] = [], audioAssetIDs:[UUID]? = nil, audioCuts:[MulticamCut]? = nil) { self.id=id; self.angleAssetIDs=angleAssetIDs; self.masterAudioAssetID=masterAudioAssetID; self.cuts=cuts; self.audioAssetIDs=audioAssetIDs; self.audioCuts=audioCuts }
}
public struct ProjectSettings: Codable, Equatable, Sendable {
    public var width: Int; public var height: Int; public var frameRate: FrameRate; public var audioSampleRate: Int
    public init(width: Int = 1920, height: Int = 1080, frameRate: FrameRate = .init(), audioSampleRate: Int = 48000) { self.width=width; self.height=height; self.frameRate=frameRate; self.audioSampleRate=audioSampleRate }
}
public struct MusicalGrid: Codable, Equatable, Sendable {
    public var bpm: Double; public var offset: RationalTime; public var beatsPerBar: Int; public var subdivision: Int
    public var anchors: [BeatAnchor]?; public var swing: Double?; public var beatUnit: Int?
    public init(bpm: Double = 120, offset: RationalTime = .zero, beatsPerBar: Int = 4, subdivision: Int = 1, anchors: [BeatAnchor]? = nil, swing: Double? = nil, beatUnit: Int? = nil) { self.bpm=bpm; self.offset=offset; self.beatsPerBar=beatsPerBar; self.subdivision=subdivision; self.anchors=anchors; self.swing=swing; self.beatUnit=beatUnit }
}
public struct Sequence: Codable, Equatable, Sendable {
    public var settings: ProjectSettings; public var tracks: [Track]; public var markers: [Marker]; public var multicamGroups: [MulticamGroup]; public var musicalGrid: MusicalGrid?; public var transitions: [VideoTransition]?
    public init(settings: ProjectSettings = .init(), tracks: [Track] = [], markers: [Marker] = [], multicamGroups: [MulticamGroup] = [], musicalGrid: MusicalGrid? = nil, transitions: [VideoTransition]? = nil) { self.settings=settings; self.tracks=tracks; self.markers=markers; self.multicamGroups=multicamGroups; self.musicalGrid=musicalGrid; self.transitions=transitions }
    public var duration: RationalTime { tracks.flatMap(\.clips).map(\.end).max() ?? .zero }
}
public struct ProjectDocument: Identifiable, Codable, Equatable, Sendable {
    public static let currentVersion = 7
    public var version: Int; public var id: UUID; public var name: String; public var sequence: Sequence; public var assets: [MediaAsset]
    public init(id: UUID = UUID(), name: String = "Untitled", sequence: Sequence = .init(), assets: [MediaAsset] = []) { self.version=Self.currentVersion; self.id=id; self.name=name; self.sequence=sequence; self.assets=assets }
    public static func decode(_ data: Data) throws -> Self {
        try ProjectMigration.decode(data)
    }
    public func encoded() throws -> Data { try validate(); let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]; return try encoder.encode(self) }
    public func validate() throws {
        guard version == Self.currentVersion else { throw DocumentError.unsupportedVersion(version) }
        try CamcorderDateOverlay.validate(in:self)
        let settings=sequence.settings
        guard (1...16384).contains(settings.width), (1...16384).contains(settings.height),
              (1...240000).contains(settings.frameRate.numerator), (1...1001).contains(settings.frameRate.denominator),
              Double(settings.frameRate.numerator)/Double(settings.frameRate.denominator) <= 240,
              (8000...192000).contains(settings.audioSampleRate) else { throw DocumentError.invalidTiming }
        if let grid=sequence.musicalGrid {
            guard grid.isValid else { throw DocumentError.invalidTiming }
        }
        let adjustmentIDs=Set(sequence.tracks.filter{$0.kind == .adjustment}.flatMap(\.clips).map(\.id))
        let clips=sequence.tracks.flatMap(\.clips)
        guard Set(clips.map(\.id)).count == clips.count, Set(sequence.tracks.map(\.id)).count == sequence.tracks.count, Set(assets.map(\.id)).count == assets.count else { throw DocumentError.duplicateID }
        func validTime(_ time: RationalTime, signed: Bool = false) -> Bool {
            time.timescale <= 1_000_000_000 && time.seconds.isFinite && abs(time.seconds) <= 86400 && (signed || time >= .zero)
        }
        for asset in assets { guard validTime(asset.duration), asset.duration > .zero else { throw DocumentError.invalidTiming } }
        for clip in clips {
            guard validTime(clip.start), validTime(clip.duration), clip.duration > .zero, validTime(clip.sourceStart,signed:adjustmentIDs.contains(clip.id)),
                  clip.speed.isFinite, (0.25...4).contains(clip.speed), clip.volume.baseValue.isFinite, clip.opacity.baseValue.isFinite,
                  (0...AudioSettings.maximumLinearGain).contains(clip.volume.baseValue), (0...1).contains(clip.opacity.baseValue),
                  clip.title == nil || (clip.title!.fontSize.isFinite && (1...4096).contains(clip.title!.fontSize)) else { throw DocumentError.invalidTiming }
            if let frozen=clip.freezeFrame {
                guard validTime(frozen.sourceTime),validTime(frozen.effectTimeOffset),clip.sourceStart==frozen.sourceTime,clip.audioEnabled == false,clip.title == nil,clip.graphic == nil,
                      let asset=assets.first(where:{$0.id==clip.assetID}),asset.kind == .video,frozen.sourceTime<asset.duration else{throw DocumentError.sourceBoundary}
            }
            if let audio=clip.audio, !audio.isValid { throw DocumentError.invalidTiming }
            if let graphic=clip.graphic {
                guard clip.title == nil, graphic.isValid else { throw DocumentError.invalidTiming }
            }
            if let visual=clip.visual, !visual.isValid { throw DocumentError.invalidTiming }
            if let style=clip.title?.style, !style.isValid { throw DocumentError.invalidTiming }
            if let animation=clip.title?.animation {
                guard animation.isValid, validTime(try animation.elapsedTime(at:clip.duration),signed:true) else { throw DocumentError.invalidTiming }
            }
            for effect in clip.effects ?? [] {
                guard !effect.stableID.isEmpty, effect.strength.isFinite, (0...1).contains(effect.strength), effect.parameters.values.allSatisfy(\.isFinite) else { throw DocumentError.invalidTiming }
                if let definition=NativeEffectRegistry.definition(for:effect.stableID) {
                    for parameter in definition.parameters {
                        if let value=effect.parameters[parameter.name], !parameter.range.contains(value) { throw DocumentError.invalidTiming }
                    }
                }
            }
            let end=try clip.start.checkedAdding(clip.duration)
            guard validTime(end) else { throw DocumentError.invalidTiming }
            if clip.freezeFrame == nil {
                let sourceDuration=try clip.duration.checkedScaled(by:Int64((clip.speed*1_000_000).rounded()),over:1_000_000)
                let sourceEnd=try clip.sourceStart.checkedAdding(sourceDuration)
                guard validTime(sourceEnd,signed:adjustmentIDs.contains(clip.id)) else { throw DocumentError.invalidTiming }
                if let asset=assets.first(where: { $0.id == clip.assetID }), asset.kind != .image, sourceEnd > asset.duration { throw DocumentError.sourceBoundary }
            }
            for (envelope,maximum) in [(clip.volume,AudioSettings.maximumLinearGain),(clip.opacity,1.0)] {
                guard envelope.points.allSatisfy({ point in
                    let effective=envelope.baseValue*point.value
                    return effective.isFinite && effective <= maximum
                }) else { throw DocumentError.invalidTiming }
                guard validTime(envelope.evaluationOffset,signed:true) else { throw DocumentError.invalidTiming }
                _ = try envelope.evaluationOffset.checkedAdding(clip.duration)
                let sortedPoints=envelope.points.sorted { $0.time < $1.time }
                for (left,right) in zip(sortedPoints,sortedPoints.dropFirst()) {
                    _ = try right.time.checkedSubtracting(left.time)
                }
                for point in envelope.points {
                    guard validTime(point.time), point.value.isFinite, point.value >= 0 else { throw DocumentError.invalidTiming }
                    _ = try point.time.checkedAdding(RationalTime(value:-envelope.evaluationOffset.value,timescale:envelope.evaluationOffset.timescale))
                }
            }
        }
        for track in sequence.tracks {
            let ordered=track.clips.sorted { $0.start < $1.start }
            for (left,right) in zip(ordered,ordered.dropFirst()) where left.end > right.start { throw DocumentError.overlap }
        }
        for marker in sequence.markers {
            if let color=marker.color, !color.isValid { throw DocumentError.invalidTiming }
            guard validTime(marker.time), validTime(marker.duration), validTime(try marker.time.checkedAdding(marker.duration)) else { throw DocumentError.invalidTiming }
        }
        let transitions=sequence.transitions ?? []
        guard Set(transitions.map(\.id)).count == transitions.count else { throw DocumentError.duplicateID }
        for transition in transitions {
            guard validTime(transition.duration), transition.duration > .zero, transition.color.isValid, (0...3).contains(transition.direction) else { throw DocumentError.invalidTiming }
        }
        for group in sequence.multicamGroups {
            for cuts in [group.cuts, group.audioCuts ?? []] {
                guard Set(cuts.map(\.id)).count == cuts.count, Set(cuts.map(\.time)).count == cuts.count else {throw DocumentError.duplicateID}
                for cut in cuts { guard validTime(cut.time) else { throw DocumentError.invalidTiming } }
            }
            guard group.cuts.allSatisfy({group.angleAssetIDs.contains($0.angleID)}), (group.audioCuts ?? []).allSatisfy({group.angleAssetIDs.contains($0.angleID) || $0.angleID == group.masterAudioAssetID || $0.angleID == MulticamSwitching.silenceAudioID}) else {throw DocumentError.invalidTiming}
        }
    }
}
public enum DocumentError: Error, Equatable { case unsupportedVersion(Int), invalidTiming, duplicateID, clipNotFound, trackNotFound, lockedTrack, overlap, sourceBoundary, invalidSplit }
public struct ProjectSnapshot: Sendable { public let document: ProjectDocument; public init(document: ProjectDocument) { self.document=document } }
public struct EvaluatedClip: Sendable { public let clip: Clip; public let trackID: UUID; public let sourceTime: RationalTime; public let volume: Double; public let opacity: Double }
public enum TimelineEvaluator {
    public static func evaluate(_ snapshot: ProjectSnapshot, at time: RationalTime) -> [EvaluatedClip] {
        snapshot.document.sequence.tracks.filter { !$0.isHidden }.flatMap { track in
            track.clips.filter { $0.start <= time && time < $0.end }.compactMap { clip -> EvaluatedClip? in
                guard let local=try? time.checkedSubtracting(clip.start),
                      let source=try? clip.checkedSourceTime(at:time),
                      let volume=try? clip.volume.checkedValue(at:local),
                      let opacity=try? clip.opacity.checkedValue(at:local) else { return nil }
                return EvaluatedClip(clip:clip,trackID:track.id,sourceTime:source,volume:track.isMuted ? 0 : volume,opacity:opacity)
            }
        }
    }
}
