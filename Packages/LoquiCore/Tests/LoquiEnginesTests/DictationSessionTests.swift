import Foundation
import LoquiCatalog
import Testing
@testable import LoquiEngines

private actor FakeEngine: TranscriptionEngine {
    nonisolated let model: CatalogModel
    private(set) var calls: [[Float]] = []
    private let reply: String

    init(reply: String) throws {
        model = try Catalog.bundled().models[0]
        self.reply = reply
    }

    func download(progress: @escaping @Sendable (Double) -> Void) async throws {}
    func load() async throws {}
    func unload() async {}
    func modelDirectories() -> [URL] { [] }
    func isInstalled() async -> Bool { true }
    func delete() async throws {}
    func diskUsageBytes() -> Int64? { nil }

    func transcribe(_ samples: [Float]) async throws -> String {
        calls.append(samples)
        return reply
    }
}

private struct Failure: Error {}

@Suite struct DictationSessionTests {
    private func session(_ engine: FakeEngine, loadDelay: Duration = .zero) -> DictationSession {
        DictationSession {
            try await Task.sleep(for: loadDelay)
            return engine
        }
    }

    @Test func transcribesAllAudioOnceOnlyAfterStop() async throws {
        let engine = try FakeEngine(reply: "ciao")
        let (audio, continuation) = AsyncStream.makeStream(of: [Float].self)
        let session = session(engine)

        let run = Task { try await session.run(audio: audio) }
        continuation.yield([1, 2])
        // Una pausa lunga non deve far partire la trascrizione.
        try await Task.sleep(for: .milliseconds(100))
        #expect(await engine.calls.isEmpty)

        continuation.yield([3])
        continuation.finish()

        guard case .text(let segment) = try await run.value else {
            Issue.record("Atteso testo")
            return
        }
        #expect(await engine.calls == [[1, 2, 3]])
        #expect(segment.text == "ciao")
        #expect(segment.audioSeconds == 3.0 / Double(loquiSampleRate))
    }

    /// Chi parla mentre il modello si carica non deve perdere nulla, nemmeno se ferma prima della fine.
    @Test func keepsAudioSpokenWhileTheModelIsLoading() async throws {
        let engine = try FakeEngine(reply: "ciao")
        let (audio, continuation) = AsyncStream.makeStream(of: [Float].self)
        let session = session(engine, loadDelay: .milliseconds(200))

        let run = Task { try await session.run(audio: audio) }
        continuation.yield([1, 2, 3])
        continuation.finish()

        guard case .text = try await run.value else {
            Issue.record("Atteso testo")
            return
        }
        #expect(await engine.calls == [[1, 2, 3]])
    }

    @Test func noAudioDoesNotCallTheEngine() async throws {
        let engine = try FakeEngine(reply: "ciao")
        let (audio, continuation) = AsyncStream.makeStream(of: [Float].self)
        continuation.finish()

        guard case .noText(let seconds, _) = try await session(engine).run(audio: audio) else {
            Issue.record("Atteso nessun testo")
            return
        }
        #expect(seconds == 0)
        #expect(await engine.calls.isEmpty)
    }

    @Test func emptyTranscriptionReportsAudioAndPeakLevel() async throws {
        let engine = try FakeEngine(reply: "")
        let (audio, continuation) = AsyncStream.makeStream(of: [Float].self)
        continuation.yield([0.1, -0.5, 0.2])
        continuation.finish()

        guard case .noText(let seconds, let peak) = try await session(engine).run(audio: audio) else {
            Issue.record("Atteso nessun testo")
            return
        }
        #expect(seconds == 3.0 / Double(loquiSampleRate))
        #expect(peak == 0.5)
    }

    @Test func modelLoadFailureSurfacesAfterStop() async throws {
        let session = DictationSession { throw Failure() }
        let (audio, continuation) = AsyncStream.makeStream(of: [Float].self)
        continuation.yield([1])
        continuation.finish()

        await #expect(throws: Failure.self) {
            _ = try await session.run(audio: audio)
        }
    }
}
