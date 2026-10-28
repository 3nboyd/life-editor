import Testing
import Foundation
@preconcurrency import AVFoundation
import LifeCore
@testable import LifeMedia

@MainActor struct TrackSoloRenderTests {
    @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"] == "1"))
    func soloPreparationAndExportUseIdenticalAdditiveRouting() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("life-solo-\(UUID())")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:directory)}
        let pipeline=MediaPipeline(),format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
        var assets=[MediaAsset](),tracks=[Track]()
        for (index,amplitude) in [0.1,0.2,0.4].enumerated() {
            let url=directory.appendingPathComponent("tone\(index).wav")
            do {
                let file=try AVAudioFile(forWriting:url,settings:format.settings.merging([AVLinearPCMIsNonInterleaved:false]){_,new in new})
                let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:48000)!;buffer.frameLength=48000
                for n in 0..<48000 {let value=Float(sin(Double(n)*2 * .pi * 1000/48000)*amplitude);for channel in 0..<2{buffer.floatChannelData![channel][n]=value}}
                try file.write(from:buffer)
            }
            let asset=try await pipeline.probe(url).asset;assets.append(asset)
            tracks.append(.init(name:"Tone \(index)",kind:index==0 ? .video:.audio,clips:[.init(assetID:asset.id,duration:.init(value:1,timescale:1))],isSoloed:index<2))
        }
        tracks.append(.init(name:"Visible title",kind:.title,clips:[.init(duration:.init(value:1,timescale:1),title:.init(text:"Solo",fontSize:20))]))
        var document=ProjectDocument(sequence:.init(settings:.init(width:64,height:64),tracks:tracks),assets:assets)
        let prepared=try await pipeline.prepare(.init(document:document))
        #expect(try await prepared.playerItem.asset.loadTracks(withMediaType:.audio).count==2)
        #expect(prepared.playerItem.videoComposition != nil)
        let measured=try await pipeline.measure(.init(document:document))
        #expect(abs(measured.peakDBFS-20*log10(0.3))<0.01)
        let output=directory.appendingPathComponent("solo.wav")
        try await pipeline.export(.init(document:document),to:output,options:.init(format:.wav))
        let file=try AVAudioFile(forReading:output),buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length))!
        try file.read(into:buffer)
        #expect(buffer.frameLength==48000)
        var peak:Float=0
        for n in 0..<Int(buffer.frameLength){peak=max(peak,abs(buffer.floatChannelData![0][n]))}
        #expect(abs(Double(peak)-0.3)<0.0001)
        document.sequence.tracks[1].isMuted=true
        let muted=try await pipeline.prepare(.init(document:document))
        #expect(try await muted.playerItem.asset.loadTracks(withMediaType:.audio).count==1)
        #expect(abs(try await pipeline.measure(.init(document:document)).peakDBFS+20)<0.01)
    }
}
