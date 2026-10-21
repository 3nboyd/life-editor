import Foundation

public struct CaptionCue: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var start: RationalTime
    public var duration: RationalTime
    public var text: String
    public init(id: UUID = UUID(), start: RationalTime, duration: RationalTime, text: String) { self.id=id; self.start=start; self.duration=duration; self.text=text }
    public var clip: Clip { Clip(id:id,name:"Caption",start:start,duration:duration,title:TitleContent(text:text,fontSize:48)) }
}
public enum SRTError: Error, Equatable { case invalidCue(Int) }
public enum SRT {
    public static func parse(_ text: String) throws -> [CaptionCue] {
        let normalized=text.replacingOccurrences(of:"\u{feff}",with:"").replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n")
        let blocks=normalized.components(separatedBy:"\n\n").filter { !$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }
        return try blocks.enumerated().map { index, block in
            var lines=block.components(separatedBy:"\n")
            if let first=lines.first, Int(first.trimmingCharacters(in:.whitespaces)) != nil { lines.removeFirst() }
            guard let timing=lines.first else { throw SRTError.invalidCue(index+1) }
            let bounds=timing.components(separatedBy:" --> ")
            guard bounds.count == 2, let start=milliseconds(bounds[0]), let end=milliseconds(bounds[1]), end > start else { throw SRTError.invalidCue(index+1) }
            lines.removeFirst()
            while lines.last == "" { lines.removeLast() }
            guard !lines.isEmpty else { throw SRTError.invalidCue(index+1) }
            return CaptionCue(start:.init(value:start,timescale:1000),duration:.init(value:end-start,timescale:1000),text:lines.joined(separator:"\n"))
        }
    }
    public static func encode(_ cues: [CaptionCue]) throws -> String {
        try cues.sorted { $0.start < $1.start }.enumerated().map { index,cue in
            guard cue.start >= .zero, cue.duration > .zero, !cue.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw SRTError.invalidCue(index+1) }
            let end=try cue.start.checkedAdding(cue.duration)
            return "\(index+1)\n\(stamp(cue.start)) --> \(stamp(end))\n\(cue.text)\n"
        }.joined(separator:"\n")
    }
    private static func milliseconds(_ input: String) -> Int64? {
        let pieces=input.trimmingCharacters(in:.whitespaces).split(whereSeparator: { $0 == ":" || $0 == "," })
        guard pieces.count == 4, pieces[0].count >= 2, pieces[1].count == 2, pieces[2].count == 2, pieces[3].count == 3,
              let h=Int64(pieces[0]), let m=Int64(pieces[1]), let s=Int64(pieces[2]), let ms=Int64(pieces[3]), (0...23).contains(h), (0...59).contains(m), (0...59).contains(s), (0...999).contains(ms) else { return nil }
        return ((h*60+m)*60+s)*1000+ms
    }
    private static func stamp(_ time: RationalTime) -> String {
        let ms=Int64((time.seconds*1000).rounded())
        return String(format:"%02lld:%02lld:%02lld,%03lld",ms/3600000,(ms/60000)%60,(ms/1000)%60,ms%1000)
    }
}
