import Foundation
import Accelerate
import LifeCore

extension AudioAnalyzer {
    /// Explicit matched source anchors, never inferred from independent tails.
    /// Search grows by ±1% of elapsed source time, covering 36 seconds/hour.
    /// Weak/repetitive windows remain unavailable for automatic correction.
    public nonisolated static func drift(reference:AudioFingerprint,other:AudioFingerprint,coarseOffset:Double)throws->AffineDriftCorrection? {
        let rate=reference.samplesPerSecond
        guard rate.isFinite,rate>0,rate<=1000,rate==other.samplesPerSecond,coarseOffset.isFinite,abs(coarseOffset)<=120,
              reference.values.count<=4_000_000,other.values.count<=4_000_000,
              reference.values.allSatisfy(\.isFinite),other.values.allSatisfy(\.isFinite) else{return nil}
        try Task.checkCancellation()
        let referenceDuration=Double(reference.values.count)/rate,otherDuration=Double(other.values.count)/rate
        guard referenceDuration.isFinite,otherDuration.isFinite,(0...86400).contains(referenceDuration),(0...86400).contains(otherDuration) else{return nil}
        let start=max(0,coarseOffset),end=min(referenceDuration,otherDuration+coarseOffset)
        guard end-start>=180 else{return nil}
        let margin=2+0.01*max(abs(start-coarseOffset),abs(end-coarseOffset))
        let centers=[start+15+margin,(start+end)/2,end-15-margin]
        guard centers[0]<centers[1],centers[1]<centers[2] else{return nil}
        var anchors:[DriftAnchor]=[]
        for center in centers {
            try Task.checkCancellation()
            guard let anchor=try matchedAnchor(reference:reference,other:other,center:center,coarseOffset:coarseOffset) else{return nil}
            anchors.append(anchor)
        }
        let slope=(anchors[2].referenceSeconds-anchors[0].referenceSeconds)/(anchors[2].sourceSeconds-anchors[0].sourceSeconds)
        guard slope.isFinite else{return nil}
        // Matching a warped window can bias its representative center towards
        // its strongest transient. Include that uncertainty, not just one hop.
        for index in anchors.indices{anchors[index].uncertaintySeconds += 15*abs(slope-1)}
        return try AffineDriftCorrection.fit(early:anchors[0],middle:anchors[1],late:anchors[2])
    }
    private nonisolated static func matchedAnchor(reference:AudioFingerprint,other:AudioFingerprint,center:Double,coarseOffset:Double)throws->DriftAnchor? {
        let rate=reference.samplesPerSecond,n=Int((30*rate).rounded()),aStart=Int(((center-15)*rate).rounded())
        guard aStart>=0,n>1,aStart+n<=reference.values.count else{return nil}
        let expected=Double(aStart)/rate-coarseOffset,span=max(2,abs(center-coarseOffset)*0.01+2)
        let first=max(0,Int(floor((expected-span)*rate))),last=min(other.values.count-n,Int(ceil((expected+span)*rate)))
        guard first<=last else{return nil}
        let a=Array(reference.values[aStart..<(aStart+n)]),mean=a.reduce(0.0){$0+Double($1)}/Double(n)
        let centered=a.map{Float(Double($0)-mean)},energy=centered.reduce(0.0){$0+Double($1)*Double($1)}
        guard energy>1e-12 else{return nil}
        let b=Array(other.values[first..<(last+n)])
        var sum=[Double](repeating:0,count:b.count+1),squares=sum
        for i in b.indices{let value=Double(b[i]);sum[i+1]=sum[i]+value;squares[i+1]=squares[i]+value*value}
        var scores:[Double]=[];scores.reserveCapacity(last-first+1)
        var best = -Double.infinity,bestIndex=0
        for lag in 0...(last-first) {
            try Task.checkCancellation()
            var dot:Float=0
            centered.withUnsafeBufferPointer{a in b.withUnsafeBufferPointer{b in vDSP_dotpr(a.baseAddress!,1,b.baseAddress!+lag,1,&dot,vDSP_Length(n))}}
            let total=sum[lag+n]-sum[lag],variance=max(0,squares[lag+n]-squares[lag]-total*total/Double(n))
            let score=Double(dot)/max(1e-20,sqrt(energy*variance))
            scores.append(score)
            if score>best{best=score;bestIndex=lag}
        }
        let exclusion=max(2,Int(rate*0.25))
        let second=scores.enumerated().filter{abs($0.offset-bestIndex)>exclusion}.map(\.element).max() ?? 0
        guard best.isFinite,second.isFinite else{return nil}
        let confidence=min(1,max(0,best))*min(1,max(0,(best-second)/max(0.1,best))*2)
        guard confidence>=0.6 else{return nil}
        return .init(sourceSeconds:Double(first+bestIndex)/rate+Double(n)/(2*rate),referenceSeconds:Double(aStart)/rate+Double(n)/(2*rate),confidence:confidence,uncertaintySeconds:1/rate)
    }
}
