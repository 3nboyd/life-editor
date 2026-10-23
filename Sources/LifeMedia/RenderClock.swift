import Foundation
import LifeCore

/// Display/effect seconds only: never round-trip these values into document,
/// media, or automation timestamps. Valid rational inputs can have a combined
/// denominator too large to represent; seeded effects and wall clocks already
/// evaluate in Double and can safely consume the scalar fallback.
enum RenderClock {
    static func sourceSeconds(for clip:Clip,at time:RationalTime)->Double? {
        guard clip.speed.isFinite,(0.25...4).contains(clip.speed) else{return nil}
        if let source=try? clip.checkedSourceTime(at:time),source.seconds.isFinite{return source.seconds}
        let seconds=clip.freezeFrame?.sourceTime.seconds ?? (clip.sourceStart.seconds+(time.seconds-clip.start.seconds)*clip.speed)
        return seconds.isFinite ? seconds:nil
    }
}
