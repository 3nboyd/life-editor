import Testing
@preconcurrency import AVFoundation
import LifeCore
import LifeMedia

@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"]=="1"))
func markerAlignedSourceImpulseMatchesPreviewExportAndReopenedProject()async throws{
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("life-marker-render-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:directory)}
    let format=try #require(AVAudioFormat(standardFormatWithSampleRate:48000,channels:1))
    func source(_ name:String,impulse:Int)throws->URL{
        let url=directory.appendingPathComponent(name+".wav")
        let buffer=try #require(AVAudioPCMBuffer(pcmFormat:format,frameCapacity:96000));buffer.frameLength=96000
        let channel=try #require(buffer.floatChannelData)[0]
        for index in 0..<96000{channel[index]=index==impulse ? 0.5:0}
        try AVAudioFile(forWriting:url,settings:format.settings).write(from:buffer)
        return url
    }
    let refURL=try source("reference",impulse:48000),targetURL=try source("target",impulse:24000)
    let reference=MediaAsset(url:refURL,kind:.audio,duration:.init(value:2,timescale:1)),target=MediaAsset(url:targetURL,kind:.audio,duration:.init(value:2,timescale:1))
    let a=Clip(assetID:reference.id,duration:reference.duration),b=Clip(assetID:target.id,duration:target.duration)
    let x=Marker(time:.init(value:1,timescale:1),clipID:a.id),y=Marker(time:.init(value:1,timescale:2),clipID:b.id)
    let original=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Ref",kind:.audio,clips:[a],isMuted:true),Track(name:"Aligned",kind:.audio,clips:[b])],markers:[x,y]),assets:[reference,target])
    let alignment=try MarkerSynchronization.alignment(referenceMarkerID:x.id,targetMarkerID:y.id,in:original)
    let editor=ProjectEditor(document:original);try editor.perform(.move(clipID:b.id,to:alignment.offset))
    let package=directory.appendingPathComponent("aligned.lifeedit");try ProjectPackage.write(editor.document,to:package)
    let reopened=try ProjectPackage.read(from:package);#expect(reopened==editor.document)
    let pipeline=MediaPipeline(),snapshot=ProjectSnapshot(document:reopened),prepared=try await pipeline.prepare(snapshot)
    func read(_ asset:AVAsset,mix:AVAudioMix?)async throws->[Float]{
        let tracks=try await asset.loadTracks(withMediaType:.audio),reader=try AVAssetReader(asset:asset)
        let output=AVAssetReaderAudioMixOutput(audioTracks:tracks,audioSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:48000,AVNumberOfChannelsKey:2,AVLinearPCMBitDepthKey:32,AVLinearPCMIsFloatKey:true,AVLinearPCMIsNonInterleaved:false])
        output.audioMix=mix;reader.add(output);try #require(reader.startReading())
        var result:[Float]=[]
        while let sample=output.copyNextSampleBuffer(),let block=CMSampleBufferGetDataBuffer(sample){
            let bytes=CMBlockBufferGetDataLength(block);var samples=[Float](repeating:0,count:bytes/4)
            let status=samples.withUnsafeMutableBytes{CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:bytes,destination:$0.baseAddress!)}
            try #require(status==noErr);result+=stride(from:0,to:samples.count,by:2).map{samples[$0]}
        }
        try #require(reader.status == .completed);return result
    }
    let preview=try await read(prepared.playerItem.asset,mix:prepared.playerItem.audioMix)
    let output=directory.appendingPathComponent("aligned.wav");try await pipeline.export(snapshot,to:output,options:.init(format:.wav))
    let exported=try await read(AVURLAsset(url:output),mix:nil)
    #expect(preview.count==exported.count)
    let previewPeak:Int?=preview.indices.max {left,right in abs(preview[left])<abs(preview[right])}
    let exportedPeak:Int?=exported.indices.max {left,right in abs(exported[left])<abs(exported[right])}
    let matches=zip(preview,exported).allSatisfy {left,right in abs(left-right)<0.00005}
    #expect(previewPeak==48000);#expect(exportedPeak==48000);#expect(matches)
    editor.undo();#expect(editor.document==original)
}
