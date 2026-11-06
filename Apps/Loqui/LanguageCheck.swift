import Foundation
import LoquiCatalog
import LoquiEngines

/// Prova multilingua lanciata dal Mac: trascrive una clip per lingua con ogni motore e salva il testo.
/// Risultati in `Documents/language-check/`, con una voce per coppia motore-lingua.
enum LanguageCheck {
    struct Entry: Codable {
        let model: String
        let language: String
        let text: String?
        let error: String?
        let seconds: Double?
    }

    private static let modelIDs = ["parakeet-ultra", "whisper-small", "apple-speechanalyzer"]

    static func run(catalog: Catalog) async {
        let clips = Bundle.main.urls(forResourcesWithExtension: "wav", subdirectory: "LanguageClips") ?? []
        var entries: [Entry] = []
        for id in modelIDs {
            guard let model = catalog.model(id: id) else { continue }
            for clip in clips.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let language = clip.deletingPathExtension().lastPathComponent
                guard model.supports(language) else { continue }
                entries.append(await check(model: model, language: language, clip: clip))
                save(entries)
            }
        }
        let directory = resultsDirectory
        try? "done".write(to: directory.appending(path: "done.txt"), atomically: true, encoding: .utf8)
    }

    /// Clip con due lingue nella stessa dettatura. Per ogni motore prova le impostazioni di lingua possibili.
    static func runMixed(catalog: Catalog) async {
        await AppleSpeechEngine.releaseReservedLocales(keeping: ["it"])
        let clips = (Bundle.main.urls(forResourcesWithExtension: "wav", subdirectory: "LanguageClips") ?? [])
            .filter { $0.lastPathComponent.hasPrefix("mix-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let setups: [(id: String, language: String)] = [
            ("parakeet-ultra", "it"),
            ("whisper-large-v3-turbo", "it"),
            ("whisper-large-v3-turbo", WhisperEngine.automaticLanguage),
            ("whisper-small", "it"),
            ("whisper-small", WhisperEngine.automaticLanguage),
            ("apple-speechanalyzer", "it"),
        ]
        var entries: [Entry] = []
        for setup in setups {
            guard let model = catalog.model(id: setup.id) else { continue }
            for clip in clips {
                var entry = await check(model: model, language: setup.language, clip: clip)
                entry = Entry(
                    model: model.id,
                    language: "\(setup.language) \(clip.deletingPathExtension().lastPathComponent)",
                    text: entry.text,
                    error: entry.error,
                    seconds: entry.seconds
                )
                entries.append(entry)
                save(entries, name: "mixed.json")
            }
        }
        try? "done".write(to: resultsDirectory.appending(path: "mixed-done.txt"), atomically: true, encoding: .utf8)
    }

    private static func check(model: CatalogModel, language: String, clip: URL) async -> Entry {
        do {
            let engine = try EngineFactory.make(model: model, language: language)
            if await !engine.isInstalled() {
                try await engine.download { _ in }
            }
            try await engine.load()
            let samples = try loadSamples(from: clip)
            let start = ContinuousClock.now
            let text = try await engine.transcribe(samples)
            let parts = (ContinuousClock.now - start).components
            await engine.unload()
            let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
            return Entry(model: model.id, language: language, text: text, error: nil, seconds: seconds)
        } catch {
            return Entry(model: model.id, language: language, text: nil, error: String(describing: error), seconds: nil)
        }
    }

    private static var resultsDirectory: URL {
        URL.documentsDirectory.appending(path: "language-check", directoryHint: .isDirectory)
    }

    private static func save(_ entries: [Entry], name: String = "results.json") {
        let directory = resultsDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: directory.appending(path: name), options: .atomic)
        }
    }
}
