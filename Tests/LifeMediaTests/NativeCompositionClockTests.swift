import Foundation
import Testing
@preconcurrency import AVFoundation
import LifeCore
@testable import LifeMedia

@Test func nativeCompositionEndpointsStaySharedBoundedAndSamplePrecise()throws {
    for scale:CMTimeScale in [8000,44100,48000,96000,192000,600000] {
        let boundary=RationalTime(value:31975,timescale:16054)
        let first=try NativeCompositionClock.range(from:.zero,to:boundary,scale:scale)
        let second=try NativeCompositionClock.range(from:boundary,to:.init(value:250000,timescale:1047),scale:scale)
        #expect(CMTimeCompare(CMTimeRangeGetEnd(first),second.start)==0)
        #expect(abs(second.start.seconds-boundary.seconds)<=0.5/Double(scale)+1e-10)
        let hour=RationalTime(value:3600*16054+31975,timescale:16054)
        let native=try NativeCompositionClock.time(hour,scale:scale)
        #expect(abs(native.seconds-hour.seconds)<=0.5/Double(scale)+1e-10)
    }
    let below=RationalTime(value:8_640_000_000_049_999,timescale:60_000_000_000)
    let above=RationalTime(value:8_640_000_000_050_001,timescale:60_000_000_000)
    #expect(try NativeCompositionClock.time(below,scale:600000).value==86_400_000_000)
    #expect(try NativeCompositionClock.time(above,scale:600000).value==86_400_000_001)
    let frame=RationalTime(value:1001,timescale:30000)
    #expect(CMTimeCompare(try NativeCompositionClock.time(frame,scale:600000),frame.cmTime)==0)
    #expect(throws:MediaError.self){try NativeCompositionClock.range(from:.zero,to:.init(value:1,timescale:1000000),scale:8000)}
    #expect(throws:MediaError.self){try NativeCompositionClock.range(from:.init(value:2,timescale:1),to:.init(value:1,timescale:1),scale:48000)}
    let pcmEnd=CMTime(value:48000,timescale:48000)
    let rounding=try NativeCompositionClock.range(from:.zero,to:.init(value:48001,timescale:48000),scale:48000,pcmEnd:pcmEnd)
    #expect(CMTimeCompare(CMTimeRangeGetEnd(rounding),pcmEnd)==0)
    #expect(throws:MediaError.self){try NativeCompositionClock.range(from:.zero,to:.init(value:48002,timescale:48000),scale:48000,pcmEnd:pcmEnd)}
}
