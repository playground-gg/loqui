import Foundation

public struct DictatedSegment: Sendable, Identifiable {
    public let id = UUID()
    public let text: String
    public let audioSeconds: Double
    /// Dallo stop al testo pronto. Comprende l'eventuale attesa del caricamento del modello.
    public let stopToTextSeconds: Double
}

public enum DictationResult: Sendable {
    case text(DictatedSegment)
    /// Audio registrato ma nessun testo: `peakLevel` distingue un microfono muto da un parlato non capito.
    case noText(audioSeconds: Double, peakLevel: Float)
}

/// Dettatura a tocchi: raccoglie l'audio finché lo stream non si chiude, cioè finché l'utente
/// non tocca di nuovo il pulsante, poi trascrive tutto insieme. Le pause non interrompono nulla.
///
/// L'audio si raccoglie da subito anche se il modello si sta ancora caricando, così non si perde
/// quello che l'utente dice nel frattempo.
public actor DictationSession {
    private let prepareEngine: @Sendable () async throws -> any TranscriptionEngine

    public init(prepareEngine: @escaping @Sendable () async throws -> any TranscriptionEngine) {
        self.prepareEngine = prepareEngine
    }

    /// `onLevel` riceve il picco del microfono al massimo dieci volte al secondo.
    public func run(
        audio: AsyncStream<[Float]>,
        onLevel: (@Sendable (Float) -> Void)? = nil
    ) async throws -> DictationResult {
        let preparation = Task { [prepareEngine] in try await prepareEngine() }

        var samples: [Float] = []
        var lastLevel = ContinuousClock.now
        var peakSinceLastLevel: Float = 0
        for await chunk in audio {
            samples.append(contentsOf: chunk)
            guard let onLevel else { continue }
            peakSinceLastLevel = chunk.reduce(peakSinceLastLevel) { max($0, abs($1)) }
            if ContinuousClock.now - lastLevel >= .milliseconds(100) {
                onLevel(peakSinceLastLevel)
                peakSinceLastLevel = 0
                lastLevel = .now
            }
        }

        let start = ContinuousClock.now
        let audioSeconds = Double(samples.count) / Double(loquiSampleRate)
        let engine = try await preparation.value
        guard !samples.isEmpty else { return .noText(audioSeconds: 0, peakLevel: 0) }

        let text = try await engine.transcribe(samples)
        guard !text.isEmpty else {
            let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
            return .noText(audioSeconds: audioSeconds, peakLevel: peak)
        }
        return .text(
            DictatedSegment(
                text: text,
                audioSeconds: audioSeconds,
                stopToTextSeconds: (ContinuousClock.now - start).seconds
            ))
    }
}

extension Duration {
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
