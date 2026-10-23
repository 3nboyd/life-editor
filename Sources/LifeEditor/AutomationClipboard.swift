import Foundation
import AppKit
import LifeCore

enum AutomationClipboardError:Error,LocalizedError {
    case invalid,version,lane,range,selection,limit
    var errorDescription:String?{switch self{
    case .invalid:return "The clipboard contains invalid automation points."
    case .version:return "This automation clipboard format is unsupported."
    case .lane:return "Paste into the same automation lane."
    case .range:return "Move the playhead so all pasted points fit inside the clip."
    case .limit:return "Copy at most 10,000 points (1 MB)."
    case .selection:return "Select an automation point to copy."
    }}
}
/// Raw wire values are checked before constructing, comparing, or adding rational times.
struct AutomationClipboardTime:Codable {
    let value:Int64;let timescale:Int64
    init(_ time:RationalTime){value=time.value;timescale=time.timescale}
    func checked()throws->RationalTime{
        guard (1...1_000_000_000).contains(timescale),value>=0 else{throw AutomationClipboardError.invalid}
        let time=RationalTime(value:value,timescale:timescale)
        guard time.seconds.isFinite,time.seconds<=86400 else{throw AutomationClipboardError.invalid};return time
    }
}
struct AutomationClipboardPoint:Codable {
    let offset:AutomationClipboardTime;let effectiveValue:Double;let interpolation:Interpolation
}
struct AutomationPointClipboard:Codable {
    static let type=NSPasteboard.PasteboardType("org.lifeeditor.automation-points.v1")
    static let maximumBytes=1_000_000
    let version:Int;let lane:String;let points:[AutomationClipboardPoint]
    func checked(for target:AutomationLane)throws->[(offset:RationalTime,value:Double,curve:Interpolation)]{
        guard version==1 else{throw AutomationClipboardError.version}
        guard lane=="volume" || lane=="opacity" else{throw AutomationClipboardError.invalid}
        guard lane==target.rawValue else{throw AutomationClipboardError.lane}
        guard points.count<=10000 else{throw AutomationClipboardError.limit}
        guard !points.isEmpty else{throw AutomationClipboardError.invalid}
        let values=try points.map{point in
            let time=try point.offset.checked()
            guard point.effectiveValue.isFinite,(0...target.maximumValue).contains(point.effectiveValue) else{throw AutomationClipboardError.invalid}
            return (offset:time,value:point.effectiveValue,curve:point.interpolation)
        }
        guard values[0].offset == .zero else{throw AutomationClipboardError.invalid}
        for (a,b) in zip(values,values.dropFirst()){guard a.offset<b.offset else{throw AutomationClipboardError.invalid}}
        return values
    }
    static func read(from pasteboard:NSPasteboard)throws->Self{
        guard let data=pasteboard.data(forType:type) else{throw AutomationClipboardError.invalid}
        guard data.count<=maximumBytes else{throw AutomationClipboardError.limit}
        return try JSONDecoder().decode(Self.self,from:data)
    }
}
