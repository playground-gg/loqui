@preconcurrency import AVFoundation
import Foundation
import LoquiCatalog
import Speech

/// SpeechAnalyzer con `SpeechTranscriber`. I modelli della lingua li gestisce iOS.
public actor AppleSpeechEngine: TranscriptionEngine {
    public nonisolated let model: CatalogModel
    private let requestedLocale: Locale
    private var locale: Locale?
    private var format: AVAudioFormat?

    init(model: CatalogModel, language: String) {
        self.model = model
        requestedLocale = Locale(identifier: language)
    }

    private func resolveLocale() async throws -> Locale {
        if let locale { return locale }
        guard SpeechTranscriber.isAvailable else {
            throw EngineError.unavailable("SpeechTranscriber non è disponibile su questo dispositivo.")
        }
        guard let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw EngineError.unavailable("SpeechTranscriber non supporta \(requestedLocale.identifier).")
        }
        locale = resolved
        return resolved
    }

    public func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        let locale = try await resolveLocale()
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let reserved = await AssetInventory.reservedLocales
        let isReserved = reserved.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
        if !isReserved, reserved.count >= AssetInventory.maximumReservedLocales {
            throw EngineError.unavailable(
                "iOS tiene al massimo \(AssetInventory.maximumReservedLocales) lingue Apple alla volta. Rilasciane una dalla scheda del modello."
            )
        }
        _ = try await AssetInventory.reserve(locale: locale)
        progress(1)
    }

    public func isInstalled() async -> Bool {
        guard let locale = try? await resolveLocale() else { return false }
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }

    /// Libera la prenotazione: sarà iOS a decidere quando togliere davvero il modello.
    public func delete() async throws {
        let locale = try await resolveLocale()
        await unload()
        _ = await AssetInventory.release(reservedLocale: locale)
    }

    public func diskUsageBytes() -> Int64? { nil }

    /// Rilascia le lingue prenotate tranne quelle indicate.
    public static func releaseReservedLocales(keeping languages: Set<String>) async {
        for locale in await AssetInventory.reservedLocales {
            guard let code = locale.language.languageCode?.identifier, !languages.contains(code) else { continue }
            _ = await AssetInventory.release(reservedLocale: locale)
        }
    }

    public func load() async throws {
        let locale = try await resolveLocale()
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw EngineError.unavailable("Il modello italiano di Apple non è installato.")
        }
        self.format = format
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)
        await analyzer.cancelAndFinishNow()
    }

    public func unload() async {
        format = nil
    }

    public func transcribe(_ samples: [Float]) async throws -> String {
        guard let locale, let format else { throw EngineError.notLoaded }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let buffer = try Self.convert(samples, to: format)
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)

        let collector = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }

        try await analyzer.start(inputSequence: stream)
        continuation.yield(AnalyzerInput(buffer: buffer))
        continuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func modelDirectories() -> [URL] { [] }

    private static func convert(_ samples: [Float], to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let source = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(loquiSampleRate),
            channels: 1,
            interleaved: false
        ),
            let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count)),
            let converter = AVAudioConverter(from: source, to: format)
        else { throw EngineError.unavailable("Conversione audio non disponibile.") }

        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { pointer in
            input.floatChannelData?[0].update(from: pointer.baseAddress!, count: samples.count)
        }

        let ratio = format.sampleRate / source.sampleRate
        let capacity = AVAudioFrameCount(Double(samples.count) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw EngineError.unavailable("Conversione audio non disponibile.")
        }

        nonisolated(unsafe) var delivered = false
        nonisolated(unsafe) let unsafeInput = input
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if delivered {
                status.pointee = .endOfStream
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return unsafeInput
        }
        if let conversionError { throw conversionError }
        return output
    }
}
