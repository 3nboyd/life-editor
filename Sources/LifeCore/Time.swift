import Foundation

/// Reduced rational seconds. No floating-point values are serialized for timeline positions.
public struct RationalTime: Codable, Hashable, Sendable, Comparable, AdditiveArithmetic {
    public let value: Int64
    public let timescale: Int64
    public init(value: Int64, timescale: Int64) {
        precondition(timescale > 0, "Time scale must be positive")
        let divisor = Self.gcd(value.magnitude, UInt64(timescale))
        self.value = value / Int64(divisor)
        self.timescale = timescale / Int64(divisor)
    }
    public static let zero = RationalTime(value: 0, timescale: 1)
    public var seconds: Double { Double(value) / Double(timescale) }
    private static func gcd(_ a: UInt64, _ b: UInt64) -> UInt64 {
        var a = a; var b = b
        while b != 0 { (a,b) = (b,a % b) }; return max(1,a)
    }
    public static func + (lhs: Self, rhs: Self) -> Self {
        let g = Int64(gcd(UInt64(lhs.timescale), UInt64(rhs.timescale)))
        return Self(value: lhs.value * (rhs.timescale/g) + rhs.value * (lhs.timescale/g), timescale: lhs.timescale * (rhs.timescale/g))
    }
    public static func - (lhs: Self, rhs: Self) -> Self { lhs + Self(value: -rhs.value, timescale: rhs.timescale) }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        let a = lhs.value.multipliedFullWidth(by: rhs.timescale)
        let b = rhs.value.multipliedFullWidth(by: lhs.timescale)
        return a.high == b.high ? a.low < b.low : a.high < b.high
    }
    public func scaled(by numerator: Int64, over denominator: Int64 = 1) -> Self {
        precondition(denominator > 0)
        let g1 = Int64(Self.gcd(value.magnitude, UInt64(denominator)))
        let g2 = Int64(Self.gcd(numerator.magnitude, UInt64(timescale)))
        return Self(value: (value/g1)*(numerator/g2), timescale: (timescale/g2)*(denominator/g1))
    }
    public func checkedAdding(_ other: Self) throws -> Self {
        let g = Int64(Self.gcd(UInt64(timescale), UInt64(other.timescale)))
        let a=value.multipliedReportingOverflow(by:other.timescale/g)
        let b=other.value.multipliedReportingOverflow(by:timescale/g)
        let scale=timescale.multipliedReportingOverflow(by:other.timescale/g)
        let sum=a.partialValue.addingReportingOverflow(b.partialValue)
        guard !a.overflow, !b.overflow, !scale.overflow, !sum.overflow else { throw DocumentError.invalidTiming }
        return Self(value:sum.partialValue,timescale:scale.partialValue)
    }
    public func checkedSubtracting(_ other: Self) throws -> Self {
        guard other.value != Int64.min else { throw DocumentError.invalidTiming }
        return try checkedAdding(Self(value:-other.value,timescale:other.timescale))
    }
    public func checkedScaled(by numerator: Int64, over denominator: Int64 = 1) throws -> Self {
        guard denominator > 0 else { throw DocumentError.invalidTiming }
        let g1=Int64(Self.gcd(value.magnitude,UInt64(denominator)))
        let g2=Int64(Self.gcd(numerator.magnitude,UInt64(timescale)))
        let product=(value/g1).multipliedReportingOverflow(by:numerator/g2)
        let scale=(timescale/g2).multipliedReportingOverflow(by:denominator/g1)
        guard !product.overflow, !scale.overflow else { throw DocumentError.invalidTiming }
        return Self(value:product.partialValue,timescale:scale.partialValue)
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let value = try c.decode(Int64.self, forKey: .value)
        let scale = try c.decode(Int64.self, forKey: .timescale)
        guard scale > 0 else { throw DecodingError.dataCorruptedError(forKey: .timescale, in: c, debugDescription: "Nonpositive time scale") }
        self.init(value: value, timescale: scale)
    }
}

public struct FrameRate: Codable, Hashable, Sendable {
    public var numerator: Int64
    public var denominator: Int64
    public init(numerator: Int64 = 30, denominator: Int64 = 1) {
        precondition(numerator > 0 && denominator > 0)
        self.numerator = numerator; self.denominator = denominator
    }
    public var frameDuration: RationalTime { RationalTime(value: denominator, timescale: numerator) }
    public func time(forFrame frame: Int64) -> RationalTime { frameDuration.scaled(by: frame) }
    public func quantized(_ time: RationalTime) -> RationalTime {
        let position = time.scaled(by: numerator, over: denominator)
        let whole = position.value / position.timescale
        let remainder = position.value % position.timescale
        let roundsUp = remainder.magnitude >= UInt64(position.timescale / 2 + position.timescale % 2)
        return self.time(forFrame: whole + (roundsUp ? (position.value < 0 ? -1 : 1) : 0))
    }
}
