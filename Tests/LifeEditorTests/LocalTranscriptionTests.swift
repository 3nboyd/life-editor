import Foundation
import Testing
import Speech
import LifeCore
@testable import LifeEditor
@MainActor @Test func speechRequestAlwaysRequiresOnDeviceProcessing() {
    let request=LocalTranscription.makeRequest(url:URL(fileURLWithPath:"/tmp/local.wav"))
    #expect(request.requiresOnDeviceRecognition)
    #expect(!request.shouldReportPartialResults)
    #expect(!LocalTranscription.permitsLocalRecognition(onDeviceSupported:false,isAvailable:true))
    #expect(!LocalTranscription.permitsLocalRecognition(onDeviceSupported:true,isAvailable:false))
    #expect(LocalTranscription.permitsLocalRecognition(onDeviceSupported:true,isAvailable:true))
}
@MainActor @Test func transcriptionRejectsNonlocalInputWithoutRequestingPermission() async {
    let previous=SFSpeechRecognizer.authorizationStatus(), service=LocalTranscription()
    await #expect(throws:LocalTranscriptionError.invalidSource) { try await service.transcribe(url:URL(string:"https://example.com/recording.wav")!) }
    #expect(!service.isRunning)
    #expect(SFSpeechRecognizer.authorizationStatus() == previous)
    service.cancel() // Cancelling an idle service is a no-op.
}
@Test func transcriptionWordCuesRetainUnicodeAndSourceTiming() {
    let result=LocalTranscription.cues(from:[(1.25,0.5,"Música 🎵"),(2,0.25,"live"),(-1,1,"bad"),(1,.infinity,"bad"),(1,0,"bad")])
    #expect(result.count == 2)
    #expect(result[0].text == "Música 🎵")
    #expect(result[0].start == RationalTime(value:5,timescale:4))
    #expect(result[0].duration == RationalTime(value:1,timescale:2))
    #expect(result[1].start == RationalTime(value:2,timescale:1))
}
