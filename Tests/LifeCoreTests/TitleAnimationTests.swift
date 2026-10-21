import Testing
import Foundation
@testable import LifeCore

@MainActor struct TitleAnimationTests {
    @Test func animationClockSurvivesSplitTrimRetimeAndUndoExactly() throws {
        let animation = TitleAnimation(kind: .typewriter, duration: 2)
        let clip = Clip(duration: .init(value: 4, timescale: 1), title: .init(text: "Life Editor", animation: animation))
        let original = ProjectDocument(sequence: .init(tracks: [.init(name: "Text", kind: .title, clips: [clip])]))
        let split = ProjectEditor(document: original)
        try split.perform(.split(clipID: clip.id, at: .init(value: 1, timescale: 2)))
        let right = split.document.sequence.tracks[0].clips[1]
        #expect(try right.title!.animation!.elapsedTime(at: .init(value: 2, timescale: 3)) == RationalTime(value: 7, timescale: 6))
        split.undo(); #expect(split.document == original); split.redo()
        #expect(split.document.sequence.tracks[0].clips[1] == right)
        let editor = ProjectEditor(document: original)
        try editor.perform(.trim(clipID: clip.id, start: .init(value: 1, timescale: 2), end: .init(value: 4, timescale: 1)))
        let trimmed = editor.document
        try editor.perform(.retime(clipID: clip.id, speed: 2, preservesPitch: true))
        let changed = editor.document.sequence.tracks[0].clips[0]
        #expect(changed.title!.animation!.timeScale == RationalTime(value: 2, timescale: 1))
        #expect(try changed.title!.animation!.elapsedTime(at: .init(value: 1, timescale: 5)) == RationalTime(value: 9, timescale: 10))
        #expect(changed.title!.animation!.duration == 2)
        editor.undo(); #expect(editor.document == trimmed)
        editor.undo(); #expect(editor.document == original)
    }
    @Test func invalidAnimationRejectsAtomicallyAndLegacyFieldsRemainOptional() throws {
        let clip = Clip(duration: .init(value: 1, timescale: 1), title: .init(text: "Life"))
        let original = ProjectDocument(sequence: .init(tracks: [.init(name: "Text", kind: .title, clips: [clip])], markers: [.init(time: .zero)]))
        let decoded = try ProjectDocument.decode(original.encoded())
        #expect(decoded.sequence.tracks[0].clips[0].title?.animation == nil)
        #expect(decoded.sequence.markers[0].color == nil)
        let editor = ProjectEditor(document: original)
        for duration in [Double.nan, 0, 0.049, 10.001] {
            var invalid = original
            invalid.sequence.tracks[0].clips[0].title?.animation = .init(kind: .fade, duration: duration)
            #expect(throws: DocumentError.invalidTiming) { try editor.perform(.replace(invalid)) }
            #expect(editor.document == original && !editor.canUndo)
        }
        var colored = original
        colored.sequence.markers[0].color = .init(red: 0.2, green: 0.4, blue: 0.8)
        #expect(try ProjectDocument.decode(colored.encoded()) == colored)
        colored.sequence.markers[0].color = .init(red: 2, green: 0, blue: 0)
        #expect(throws: DocumentError.invalidTiming) { try colored.validate() }
    }
}
