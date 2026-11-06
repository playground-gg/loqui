import CoreML
import FluidAudio
import Foundation
import LoquiCatalog

public actor ParakeetEngine: TranscriptionEngine {
    public nonisolated let model: CatalogModel
    private let version: AsrModelVersion
    private var manager: AsrManager?

    /// Sotto questa durata FluidAudio rifiuta l'audio, quindi le frasi brevissime si completano con silenzio.
    private static let minimumSamples = ASRConstants.minimumRequiredSamples(forSampleRate: loquiSampleRate)

    init(model: CatalogModel) throws {
        switch model.engineModel {
        case "ultra": version = .ultra
        case "v3": version = .v3
        default: throw EngineError.unavailable("Versione Parakeet sconosciuta: \(model.engineModel)")
        }
        self.model = model
    }

    private var directory: URL { AsrModels.defaultCacheDirectory(for: version) }

    public func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        // FluidAudio compila i modelli durante il download, così la prima dettatura non paga questo costo.
        _ = try await AsrModels.download(
            version: version,
            encoderComputeUnits: .cpuAndNeuralEngine,
            progressHandler: { progress($0.fractionCompleted) }
        )
    }

    public func isInstalled() -> Bool {
        AsrModels.modelsExist(at: directory, version: version)
    }

    public func delete() async throws {
        await unload()
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    public func diskUsageBytes() -> Int64? {
        directorySize(directory)
    }

    public func load() async throws {
        let configuration = AsrModels.defaultConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        let models = try await AsrModels.load(
            from: directory,
            configuration: configuration,
            version: version,
            encoderComputeUnits: .cpuAndNeuralEngine
        )
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
    }

    public func unload() async {
        await manager?.cleanup()
        manager = nil
    }

    public func transcribe(_ samples: [Float]) async throws -> String {
        guard let manager else { throw EngineError.notLoaded }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let padded = samples.count < Self.minimumSamples
            ? samples + [Float](repeating: 0, count: Self.minimumSamples - samples.count)
            : samples
        return try await manager.transcribe(padded, decoderState: &state).text
    }

    public func modelDirectories() -> [URL] {
        [directory]
    }
}
