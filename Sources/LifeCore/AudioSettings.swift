import Foundation

public enum AudioChannelMode: String, Codable, CaseIterable, Sendable { case stereo, left, right, mono }
/// Static clip processing. The existing volume envelope remains the sole volume-automation lane.
public struct AudioSettings: Codable, Equatable, Sendable {
    public var gainDB: Double; public var pan: Double; public var channels: AudioChannelMode
    public var eqLowDB: Double; public var eqMidDB: Double; public var eqHighDB: Double
    public var limiterEnabled: Bool; public var limiterCeilingDB: Double
    public init(gainDB: Double = 0, pan: Double = 0, channels: AudioChannelMode = .stereo, eqLowDB: Double = 0, eqMidDB: Double = 0, eqHighDB: Double = 0, limiterEnabled: Bool = false, limiterCeilingDB: Double = -0.1) {
        self.gainDB=gainDB; self.pan=pan; self.channels=channels; self.eqLowDB=eqLowDB; self.eqMidDB=eqMidDB; self.eqHighDB=eqHighDB; self.limiterEnabled=limiterEnabled; self.limiterCeilingDB=limiterCeilingDB
    }
    public var isValid: Bool {
        [gainDB,pan,eqLowDB,eqMidDB,eqHighDB,limiterCeilingDB].allSatisfy(\.isFinite) &&
        (-96...24).contains(gainDB) && (-1...1).contains(pan) &&
        [eqLowDB,eqMidDB,eqHighDB].allSatisfy { (-18...18).contains($0) } && (-12...0).contains(limiterCeilingDB)
    }
    public static let maximumLinearGain=pow(10.0,24.0/20.0)
}
/// Measured values, not document state. Silence may be represented as negative infinity.
/// sampleCount counts audio frames (samples per channel), rather than interleaved scalar values.
/// loudnessLUFS must remain nil unless measured by a genuine BS.1770 loudness implementation.
public struct AudioMeasurement: Equatable, Sendable {
    public var peakDBFS: Double; public var rmsDBFS: Double; public var loudnessLUFS: Double?; public var sampleCount: Int64
    public init(peakDBFS: Double, rmsDBFS: Double, loudnessLUFS: Double? = nil, sampleCount: Int64) { self.peakDBFS=peakDBFS; self.rmsDBFS=rmsDBFS; self.loudnessLUFS=loudnessLUFS; self.sampleCount=sampleCount }
}
