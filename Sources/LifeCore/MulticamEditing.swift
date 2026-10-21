import Foundation

public enum MulticamEditing {
    /// Replaces only [start,end), restoring the original angle at the right boundary.
    /// Media and master-audio decisions are untouched.
    public static func replacingCuts(in group:MulticamGroup,from start:RationalTime,to end:RationalTime,with decisions:[MulticamCut]) throws -> MulticamGroup {
        guard start >= .zero,end>start,decisions.allSatisfy({$0.time>=start && $0.time<end && group.angleAssetIDs.contains($0.angleID)}) else{throw DocumentError.invalidTiming}
        let original=group.cuts.sorted{$0.time<$1.time}
        let initial=original.last(where:{$0.time<=start})?.angleID ?? group.angleAssetIDs.first
        let resumed=original.last(where:{$0.time<=end})?.angleID ?? group.angleAssetIDs.first
        var inside=decisions.sorted{$0.time<$1.time}
        guard Set(inside.map(\.time)).count==inside.count else{throw DocumentError.invalidTiming}
        if !inside.contains(where:{$0.time==start}),let initial{inside.insert(.init(time:start,angleID:initial),at:0)}
        var result=group
        result.cuts=original.filter{$0.time<start || $0.time>=end}+inside
        if !result.cuts.contains(where:{$0.time==end}),let resumed{result.cuts.append(.init(time:end,angleID:resumed))}
        result.cuts.sort{$0.time<$1.time}
        return result
    }
}
