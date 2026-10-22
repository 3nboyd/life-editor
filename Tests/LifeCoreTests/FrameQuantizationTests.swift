import Testing
@testable import LifeCore

@Test func frameQuantizationUsesFullWidthProductsForValidLongRationals() throws {
    let rate=FrameRate(numerator:240000,denominator:1001)
    let value=RationalTime(value:80000*999999937+1,timescale:999999937)
    let result=try rate.checkedQuantized(value)
    #expect(result==rate.time(forFrame:19180819))
    #expect(rate.quantized(value)==result)
    #expect(try rate.checkedQuantized(.init(value:-value.value,timescale:value.timescale)) == .zero-result)
    let ntsc=FrameRate(numerator:30000,denominator:1001)
    #expect(try ntsc.checkedQuantized(.init(value:1001,timescale:60000))==ntsc.frameDuration)
    #expect(try ntsc.checkedQuantized(.init(value:-1001,timescale:60000)) == .zero-ntsc.frameDuration)
    #expect(throws:DocumentError.self){try rate.checkedQuantized(.init(value:Int64.max,timescale:1))}
}
