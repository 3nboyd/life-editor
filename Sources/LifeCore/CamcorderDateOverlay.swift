import Foundation

public enum CamcorderDateFormat:String,Codable,CaseIterable,Sendable { case date,time,dateTime }
public enum CamcorderDateCorner:String,Codable,CaseIterable,Sendable { case topLeft,topRight,bottomLeft,bottomRight }
public enum CamcorderDateOrigin:String,Codable,Sendable { case manual,recorded }

/// An explicitly chosen source-zero wall clock. A fixed offset makes renders
/// independent of the machine's timezone and daylight-saving database.
public struct CamcorderDateOverlay:Codable,Equatable,Sendable {
    public var enabled:Bool
    public var sourceZeroUnixSeconds:Double
    public var utcOffsetSeconds:Int
    public var format:CamcorderDateFormat
    public var corner:CamcorderDateCorner
    public var origin:CamcorderDateOrigin
    public init(sourceZeroUnixSeconds:Double,utcOffsetSeconds:Int=0,enabled:Bool=true,format:CamcorderDateFormat = .dateTime,corner:CamcorderDateCorner = .bottomRight,origin:CamcorderDateOrigin = .manual) {
        self.sourceZeroUnixSeconds=sourceZeroUnixSeconds;self.utcOffsetSeconds=utcOffsetSeconds;self.enabled=enabled;self.format=format;self.corner=corner;self.origin=origin
    }
    public var isValid:Bool { sourceZeroUnixSeconds.isFinite && (-2208988800...4133980800).contains(sourceZeroUnixSeconds) && (-50400...50400).contains(utcOffsetSeconds) }
    public static func parse(_ text:String,origin:CamcorderDateOrigin = .manual)->Self? {
        // Timezone is mandatory; date-only and ambiguous local times are rejected.
        guard text.range(of:#"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$"#,options:.regularExpression) != nil else{return nil}
        let suffix=text.hasSuffix("Z") ? "Z":String(text.suffix(6))
        let parser=ISO8601DateFormatter();parser.formatOptions=[.withInternetDateTime]
        guard var date=parser.date(from:String(text.prefix(19))+suffix) else{return nil}
        if text.dropFirst(19).first == "." {
            let fraction=text.dropFirst(20).dropLast(suffix.count)
            guard fraction.count<=9,let value=Double("0."+fraction) else{return nil}
            date=date.addingTimeInterval(value)
        }
        var offset=0
        if !text.hasSuffix("Z") {
            let suffix=String(text.suffix(6)),parts=suffix.dropFirst().split(separator:":")
            guard parts.count==2,let hours=Int(parts[0]),let minutes=Int(parts[1]),minutes<60,hours<=14 else{return nil}
            offset=(hours*3600+minutes*60)*(suffix.first == "-" ? -1:1)
        }
        let calendarCheck=DateFormatter();calendarCheck.locale=Locale(identifier:"en_US_POSIX");calendarCheck.calendar=Calendar(identifier:.gregorian);calendarCheck.timeZone=TimeZone(secondsFromGMT:offset);calendarCheck.dateFormat="yyyy-MM-dd'T'HH:mm:ss"
        guard calendarCheck.string(from:date)==String(text.prefix(19)) else{return nil}
        let value=Self(sourceZeroUnixSeconds:date.timeIntervalSince1970,utcOffsetSeconds:offset,origin:origin)
        return value.isValid ? value:nil
    }
    public var entryText:String {
        let formatter=ISO8601DateFormatter();formatter.timeZone=TimeZone(secondsFromGMT:utcOffsetSeconds)
        let whole=floor(sourceZeroUnixSeconds),base=formatter.string(from:Date(timeIntervalSince1970:whole))
        let nanos=Int(((sourceZeroUnixSeconds-whole)*1_000_000_000).rounded())
        guard nanos>0 else{return base}
        let fraction=String(format:"%09d",nanos).replacingOccurrences(of:"0+$",with:"",options:.regularExpression)
        return String(base.prefix(19))+"."+fraction+base.dropFirst(19)
    }
    public func text(at sourceTime:RationalTime)->String {
        guard isValid,sourceTime.seconds.isFinite else{return ""}
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.calendar=Calendar(identifier:.gregorian)
        formatter.timeZone=TimeZone(secondsFromGMT:utcOffsetSeconds)
        switch format {case .date:formatter.dateFormat="yyyy-MM-dd";case .time:formatter.dateFormat="HH:mm:ss";case .dateTime:formatter.dateFormat="yyyy-MM-dd HH:mm:ss"}
        return formatter.string(from:Date(timeIntervalSince1970:floor(sourceZeroUnixSeconds+sourceTime.seconds)))
    }
    public static func validate(in document:ProjectDocument)throws {
        for track in document.sequence.tracks {for clip in track.clips {for effect in clip.effects ?? [] {
            guard let overlay=effect.camcorderDate else{continue}
            guard overlay.isValid,effect.stableID == "life.filter.VHS",track.kind != .adjustment,
                  document.assets.contains(where:{$0.id==clip.assetID && ($0.kind == .video || $0.kind == .image)}) else{throw CamcorderDateError.unsupported}
        }}}
    }
}
public enum CamcorderDateError:LocalizedError {case unsupported
    public var errorDescription:String?{"Camcorder dates require a valid date and a VHS effect on video or an image."}
}
