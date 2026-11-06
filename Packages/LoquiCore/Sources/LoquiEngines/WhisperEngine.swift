import CoreML
import Foundation
import LoquiCatalog
import WhisperKit

public actor WhisperEngine: TranscriptionEngine {
    /// Fa scegliere la lingua a Whisper invece di imporla.
    public static let automaticLanguage = "auto"

    public nonisolated let model: CatalogModel
    private let language: String
    private var whisper: WhisperKit?

    init(model: CatalogModel, language: String) {
        self.model = model
        self.language = language
    }

    private var base: URL {
        URL.applicationSupportDirectory.appending(path: "WhisperKit", directoryHint: .isDirectory)
    }

    private var folder: URL {
        base.appending(path: "models/argmaxinc/whisperkit-coreml/\(model.engineModel)", directoryHint: .isDirectory)
    }

    private var computeOptions: ModelComputeOptions {
        ModelComputeOptions(
            melCompute: .cpuAndNeuralEngine,
            audioEncoderCompute: .cpuAndNeuralEngine,
            textDecoderCompute: .cpuAndNeuralEngine
        )
    }

    public func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        _ = try await WhisperKit.download(
            variant: model.engineModel,
            downloadBase: base,
            progressCallback: { progress($0.fractionCompleted) }
        )
        // Il primo caricamento compila per il Neural Engine e scarica il tokenizer, poi resta tutto in locale.
        try await load()
        await unload()
    }

    public func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: "AudioEncoder.mlmodelc").path)
    }

    public func delete() async throws {
        await unload()
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    public func diskUsageBytes() -> Int64? {
        directorySize(folder)
    }

    public func load() async throws {
        whisper = try await WhisperKit(
            WhisperKitConfig(
                downloadBase: base,
                modelFolder: folder.path,
                tokenizerFolder: base,
                computeOptions: computeOptions,
                verbose: false,
                logLevel: .none,
                prewarm: false,
                load: true,
                download: false
            ))
    }

    public func unload() async {
        await whisper?.unloadModels()
        whisper = nil
    }

    public func transcribe(_ samples: [Float]) async throws -> String {
        guard let whisper else { throw EngineError.notLoaded }
        let detects = language == WhisperEngine.automaticLanguage
        let options = DecodingOptions(
            language: detects ? nil : language,
            usePrefillPrompt: true,
            detectLanguage: detects,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        let results = await whisper.transcribeWithResults(audioArrays: [samples], decodeOptions: options)
        guard let first = results.first else { return "" }
        return try first.get()
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func modelDirectories() -> [URL] {
        [folder]
    }
}
