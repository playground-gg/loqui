import Foundation
import LoquiCatalog

/// Campionamento comune a tutti i motori: PCM Float32 mono.
public let loquiSampleRate = 16_000

/// Contratto comune dei motori. Un fork aggiunge un motore implementando questo protocollo,
/// una voce in `models.json` e un caso in `EngineFactory`.
public protocol TranscriptionEngine: Actor {
    nonisolated var model: CatalogModel { get }

    /// Scarica ciò che manca e compila il modello per il Neural Engine. È l'unico metodo che può usare la rete.
    func download(progress: @escaping @Sendable (Double) -> Void) async throws
    func isInstalled() async -> Bool
    func delete() async throws
    /// Spazio occupato. Nil se lo gestisce iOS.
    func diskUsageBytes() -> Int64?
    func load() async throws
    func unload() async
    /// Trascrive tutta la dettatura: campioni a 16 kHz mono.
    func transcribe(_ samples: [Float]) async throws -> String
    /// Cartelle con i modelli Core ML, usate per verificare dove girano. Vuoto se le gestisce iOS.
    func modelDirectories() -> [URL]
}

public enum EngineFactory {
    public static func make(model: CatalogModel, language: String) throws -> any TranscriptionEngine {
        switch model.engine {
        case .fluidaudio: try ParakeetEngine(model: model)
        case .whisperkit: WhisperEngine(model: model, language: language)
        case .apple: AppleSpeechEngine(model: model, language: language)
        }
    }
}

public enum EngineError: LocalizedError {
    case notLoaded
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .notLoaded: "Il modello non è caricato."
        case .unavailable(let reason): reason
        }
    }
}

func directorySize(_ url: URL) -> Int64 {
    guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else {
        return 0
    }
    var total: Int64 = 0
    for case let file as URL in files {
        total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
    }
    return total
}
