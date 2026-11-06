import Foundation
import Testing
@testable import LoquiShared

@Suite struct DictationBufferTests {
    @Test func addsASpaceOnlyWhenTheTextWouldStickToAWord() {
        #expect(DictationBuffer.textToInsert("ciao", after: nil) == "ciao")
        #expect(DictationBuffer.textToInsert("ciao", after: "") == "ciao")
        #expect(DictationBuffer.textToInsert("ciao", after: "Sì") == " ciao")
        #expect(DictationBuffer.textToInsert("ciao", after: "Sì ") == "ciao")
        #expect(DictationBuffer.textToInsert("ciao", after: "riga\n") == "ciao")
        #expect(DictationBuffer.textToInsert(", ciao", after: "Sì") == ", ciao")
        #expect(DictationBuffer.textToInsert("ciao", after: "(") == "ciao")
    }

    @Test func undoRemovesInsertionsInReverseOrder() {
        var buffer = DictationBuffer()
        #expect(!buffer.canUndo)
        #expect(buffer.popLast() == nil)

        buffer.record("Ciao")
        buffer.record(" mondò")
        #expect(buffer.text == "Ciao mondò")
        #expect(buffer.popLast() == 6)
        #expect(buffer.text == "Ciao")
        #expect(buffer.popLast() == 4)
        #expect(!buffer.canUndo)
    }

    /// `deleteBackward` lavora sui caratteri visibili: un'emoji composta conta uno.
    @Test func undoCountsVisibleCharacters() {
        var buffer = DictationBuffer()
        buffer.record("👨‍👩‍👧 è")
        #expect(buffer.popLast() == 3)
    }
}

@Suite struct SharedStateTests {
    private func temporaryStore() -> SharedStore {
        SharedStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json"))
    }

    @Test func roundTripsThroughTheSharedFile() {
        let store = temporaryStore()
        #expect(store.read() == nil)
        let id = UUID()
        let state = SharedState(
            phase: .transcribing,
            level: 0.5,
            pendingText: "ciao",
            pendingID: id,
            updatedAt: Date(timeIntervalSince1970: 1000)
        )
        store.write(state)
        #expect(store.read() == state)
    }

    @Test func aFrozenRecordingCountsAsDead() {
        let start = Date(timeIntervalSince1970: 1000)
        let state = SharedState(phase: .listening, updatedAt: start)
        #expect(state.isAlive(now: start.addingTimeInterval(1)))
        #expect(!state.isAlive(now: start.addingTimeInterval(4)))
        #expect(SharedState(phase: .idle, updatedAt: start).isAlive(now: start.addingTimeInterval(9999)))
    }

    @Test func oldTextIsNotDeliverable() {
        let start = Date(timeIntervalSince1970: 1000)
        let state = SharedState(pendingText: "ciao", pendingID: UUID(), updatedAt: start)
        #expect(state.deliverableText(now: start.addingTimeInterval(10))?.text == "ciao")
        #expect(state.deliverableText(now: start.addingTimeInterval(121)) == nil)
    }
}
