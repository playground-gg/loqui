import CoreML
import Darwin
import FluidAudio
import Foundation
import LoquiShared
import Synchronization

/// Legge un file audio come campioni a 16 kHz mono.
public func loadSamples(from url: URL) throws -> [Float] {
    try AudioConverter().resampleAudioFile(url)
}

public struct ClipResult: Codable, Sendable, Identifiable {
    public var id: String { clip }
    public let clip: String
    public let audioSeconds: Double
    public let medianInferenceSeconds: Double
    public let bestInferenceSeconds: Double
    public let worstInferenceSeconds: Double
    public let rtfx: Double
    public let text: String
}

public struct ModelPlacement: Codable, Sendable, Identifiable {
    public var id: String { model }
    public let model: String
    public let neuralEnginePercent: Double
    public let gpuPercent: Double
    public let cpuPercent: Double
}

public struct BenchmarkReport: Codable, Sendable {
    public let engineID: String
    public let engineName: String
    public let device: String
    public let osVersion: String
    public let date: Date
    public let thermalStateEnd: String
    public let downloadSeconds: Double
    public let firstLoadSeconds: Double
    public let warmLoadSeconds: Double
    public let footprintBeforeMB: Double
    public let footprintLoadedMB: Double
    public let footprintPeakMB: Double
    public let footprintAfterUnloadMB: Double
    /// Misurata 15 s dopo lo scaricamento, per distinguere una cache lenta da memoria mai rilasciata.
    public let footprintSettledMB: Double?
    public let clips: [ClipResult]
    /// Vuoto per SpeechAnalyzer: i modelli li gestisce iOS e non si possono ispezionare.
    public let placement: [ModelPlacement]

    /// Tempo reale complessivo su tutte le clip.
    public var overallRTFx: Double {
        let audio = clips.map(\.audioSeconds).reduce(0, +)
        let time = clips.map(\.medianInferenceSeconds).reduce(0, +)
        return time > 0 ? audio / time : 0
    }
}

private final class PeakSampler: Sendable {
    private let peak = Mutex(0.0)
    private let running = Mutex(true)

    func start() {
        Thread.detachNewThread { [self] in
            while running.withLock({ $0 }) {
                let current = physicalFootprintMB()
                peak.withLock { $0 = max($0, current) }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }

    func stop() -> Double {
        running.withLock { $0 = false }
        return peak.withLock { $0 }
    }
}

public enum Benchmark {
    private static let runsPerClip = 3

    /// Va eseguito con il telefono sbloccato e l'app in primo piano.
    public static func run(
        engine: any TranscriptionEngine,
        clips: [URL],
        status: @escaping @Sendable (String) -> Void
    ) async throws -> BenchmarkReport {
        let clock = ContinuousClock()
        let before = physicalFootprintMB()
        let sampler = PeakSampler()
        sampler.start()

        status("Download del modello…")
        // A modello presente non si tocca la rete: WhisperKit la userebbe per ricontrollare il repository.
        let alreadyInstalled = await engine.isInstalled()
        let download = try await clock.measure {
            guard !alreadyInstalled else { return }
            try await engine.download { fraction in
                status("Download \(Int(fraction * 100))%")
            }
        }

        status("Primo caricamento…")
        let firstLoad = try await clock.measure { try await engine.load() }
        await engine.unload()

        status("Caricamento a caldo…")
        let warmLoad = try await clock.measure { try await engine.load() }

        let loaded = physicalFootprintMB()

        let converter = AudioConverter()
        var results: [ClipResult] = []
        for clip in clips.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = clip.deletingPathExtension().lastPathComponent
            status("Trascrizione \(name)…")
            let samples = try converter.resampleAudioFile(clip)
            // Il primo giro riscalda le cache e non si conta.
            var text = try await engine.transcribe(samples)
            var times: [Double] = []
            for _ in 0..<runsPerClip {
                let start = clock.now
                text = try await engine.transcribe(samples)
                times.append((clock.now - start).seconds)
            }
            times.sort()
            let audioSeconds = Double(samples.count) / Double(loquiSampleRate)
            results.append(
                ClipResult(
                    clip: name,
                    audioSeconds: audioSeconds,
                    medianInferenceSeconds: times[times.count / 2],
                    bestInferenceSeconds: times[0],
                    worstInferenceSeconds: times[times.count - 1],
                    rtfx: audioSeconds / times[times.count / 2],
                    text: text
                ))
        }

        let peak = sampler.stop()
        await engine.unload()
        let afterUnload = physicalFootprintMB()
        status("Attesa rilascio memoria…")
        try await Task.sleep(for: .seconds(15))
        let settled = physicalFootprintMB()

        status("Controllo Neural Engine…")
        let placement = await computePlacement(in: await engine.modelDirectories())

        return BenchmarkReport(
            engineID: engine.model.id,
            engineName: engine.model.name,
            device: deviceModel(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            date: Date(),
            thermalStateEnd: thermalName(ProcessInfo.processInfo.thermalState),
            downloadSeconds: download.seconds,
            firstLoadSeconds: firstLoad.seconds,
            warmLoadSeconds: warmLoad.seconds,
            footprintBeforeMB: before,
            footprintLoadedMB: loaded,
            footprintPeakMB: peak,
            footprintAfterUnloadMB: afterUnload,
            footprintSettledMB: settled,
            clips: results,
            placement: placement
        )
    }

    /// Chiede a Core ML dove intende eseguire ogni operazione dei modelli.
    private static func computePlacement(in directories: [URL]) async -> [ModelPlacement] {
        var results: [ModelPlacement] = []
        for directory in directories {
            let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for model in contents where model.pathExtension == "mlmodelc" {
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .cpuAndNeuralEngine
                guard let plan = try? await MLComputePlan.load(contentsOf: model, configuration: configuration),
                    case .program(let program) = plan.modelStructure,
                    let main = program.functions["main"]
                else { continue }
                var counts = (ane: 0, gpu: 0, cpu: 0)
                for operation in main.block.operations {
                    guard let usage = plan.deviceUsage(for: operation) else { continue }
                    switch usage.preferred {
                    case .neuralEngine: counts.ane += 1
                    case .gpu: counts.gpu += 1
                    case .cpu: counts.cpu += 1
                    @unknown default: break
                    }
                }
                let total = Double(max(counts.ane + counts.gpu + counts.cpu, 1))
                results.append(
                    ModelPlacement(
                        model: model.deletingPathExtension().lastPathComponent,
                        neuralEnginePercent: Double(counts.ane) / total * 100,
                        gpuPercent: Double(counts.gpu) / total * 100,
                        cpuPercent: Double(counts.cpu) / total * 100
                    ))
            }
        }
        return results.sorted { $0.model < $1.model }
    }

    private static func deviceModel() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(decoding: machine.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
