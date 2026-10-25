import Foundation
import LifeCore

extension EditorStore {
    static func synchronizationSourceOrigin(_ clip:Clip,in document:ProjectDocument)throws->RationalTime {
        guard clip.speed.isFinite,(0.25...4).contains(clip.speed) else{throw DocumentError.invalidTiming}
        let rate=Int64((clip.speed*1_000_000).rounded())
        do{return try clip.start.checkedSubtracting(clip.sourceStart.checkedScaled(by:1_000_000,over:rate))}
        catch{
            let seconds=clip.start.seconds-clip.sourceStart.seconds/clip.speed
            guard seconds.isFinite,abs(seconds)<=86400 else{throw DocumentError.invalidTiming}
            let sampleRate=Int64(document.sequence.settings.audioSampleRate)
            return .init(value:Int64((seconds*Double(sampleRate)).rounded()),timescale:sampleRate)
        }
    }
}
