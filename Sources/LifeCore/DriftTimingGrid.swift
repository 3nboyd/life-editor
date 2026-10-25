import Foundation

/// One shared placement grid retains exact fragment boundaries while measuring
/// the analysis-derived origin more precisely than one project audio sample.
public enum DriftTimingGrid {
    public static func scale(for times:[RationalTime],sampleRate:Int)throws->Int64 {
        guard (8000...192000).contains(sampleRate) else{throw DriftCorrectionError.invalidRange}
        var common:Int64=1
        for time in times {
            let denominator=time.timescale
            guard denominator>0,denominator<=1_000_000_000 else{throw DriftCorrectionError.invalidRange}
            var a=common,b=denominator
            while b != 0{let remainder=a%b;a=b;b=remainder}
            let product=(common/a).multipliedReportingOverflow(by:denominator)
            guard !product.overflow,product.partialValue<=1_000_000_000 else{throw DriftCorrectionError.invalidRange}
            common=product.partialValue
        }
        let multiplier=max(1,(Int64(sampleRate)+common-1)/common)
        let result=common.multipliedReportingOverflow(by:multiplier)
        guard !result.overflow,result.partialValue<=1_000_000_000 else{throw DriftCorrectionError.invalidRange}
        return result.partialValue
    }
    public static func time(seconds:Double,scale:Int64)throws->RationalTime {
        guard seconds.isFinite,abs(seconds)<=86400,scale>0,scale<=1_000_000_000 else{throw DriftCorrectionError.invalidRange}
        return .init(value:Int64((seconds*Double(scale)).rounded()),timescale:scale)
    }
    public static func translationStarts(for clips:[Clip],deltaSeconds:Double,sampleRate:Int)throws->[UUID:RationalTime] {
        guard Set(clips.map(\.id)).count==clips.count else{throw DocumentError.duplicateID}
        let grid=try scale(for:clips.flatMap{[$0.start,$0.duration]},sampleRate:sampleRate)
        let delta=try time(seconds:deltaSeconds,scale:grid)
        return try Dictionary(uniqueKeysWithValues:clips.map{($0.id,try $0.start.checkedAdding(delta))})
    }
}
