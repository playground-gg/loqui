@preconcurrency import AVFoundation
import Darwin
import Foundation
import LoquiShared
import Synchronization
import UIKit

/// Prova lanciata dal Mac: costo e tenuta dei modi di restare pronti in background, con il modello caricato.
/// Risultati in `Documents/bg-check-<scenario>.json`.
@MainActor
enum BackgroundCheck {
    struct Sample: Codable {
        let t: Double
        let state: String
        let cpuSeconds: Double
        let energyJoules: Double
        let footprintMB: Double
    }

    struct Report: Codable {
        var scenario: String
        var samples: [Sample] = []
        var loadedFootprintMB: Double?
        var setupError: String?
        var restartState: String?
        var restartError: String?
        var restartPeak: Float?
        var restartFrames: Int?
    }

    private final class Meter: Sendable {
        private let state = Mutex((peak: Float(0), frames: 0))

        func add(_ buffer: AVAudioPCMBuffer) {
            guard let channel = buffer.floatChannelData?[0] else { return }
            let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
            state.withLock {
                $0.peak = max($0.peak, peak)
                $0.frames += samples.count
            }
        }

        var snapshot: (peak: Float, frames: Int) { state.withLock { $0 } }
    }

    private nonisolated static func makeTap(_ meter: Meter) -> AVAudioNodeTapBlock {
        { buffer, _ in meter.add(buffer) }
    }

    private nonisolated static func makeSilence() -> AVAudioSourceNode {
        AVAudioSourceNode { silence, _, _, list in
            silence.pointee = true
            for buffer in UnsafeMutableAudioBufferListPointer(list) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            return noErr
        }
    }

    static func run(scenario: String, store: ModelStore) async {
        var report = Report(scenario: scenario)
        // La prova vale solo con il modello più pesante davvero in memoria.
        store.activeModelID = "parakeet-ultra"
        await store.preloadActiveEngine()
        report.loadedFootprintMB = physicalFootprintMB()

        let session = AVAudioSession.sharedInstance()
        let engine = AVAudioEngine()
        let meter = Meter()
        do {
            switch scenario {
            case "A":
                try session.setCategory(.record, mode: .default)
                try session.setActive(true)
                let format = engine.inputNode.outputFormat(forBus: 0)
                engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: makeTap(meter))
                try engine.start()
            case "B":
                try session.setCategory(.record, mode: .default)
                try session.setActive(true)
                let format = engine.inputNode.outputFormat(forBus: 0)
                engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: makeTap(meter))
                try engine.start()
                try? await Task.sleep(for: .seconds(1))
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
            default:
                try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
                let silence = makeSilence()
                engine.attach(silence)
                engine.connect(silence, to: engine.mainMixerNode, format: nil)
                try engine.start()
            }
        } catch {
            report.setupError = String(describing: error)
        }

        let start = Date()
        let startEnergy = readEnergy()
        // Nel momento in cui il Mac apre Note, l'app passa in background.
        for _ in 0..<40 where UIApplication.shared.applicationState == .active {
            try? await Task.sleep(for: .seconds(1))
        }
        for _ in 0..<14 {
            let energy = readEnergy()
            report.samples.append(Sample(
                t: Date().timeIntervalSince(start),
                state: stateName(),
                cpuSeconds: energy.cpu - startEnergy.cpu,
                energyJoules: energy.joules - startEnergy.joules,
                footprintMB: physicalFootprintMB()
            ))
            save(report)
            try? await Task.sleep(for: .seconds(5))
        }

        // Il vero test: dal background, il microfono riparte e dà segnale?
        report.restartState = stateName()
        if engine.isRunning, scenario == "A" {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        let restart = AVAudioEngine()
        let restartMeter = Meter()
        do {
            let format = restart.inputNode.outputFormat(forBus: 0)
            restart.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: makeTap(restartMeter))
            try restart.start()
            try? await Task.sleep(for: .seconds(4))
            restart.inputNode.removeTap(onBus: 0)
            restart.stop()
        } catch {
            report.restartError = String(describing: error)
        }
        report.restartPeak = restartMeter.snapshot.peak
        report.restartFrames = restartMeter.snapshot.frames
        save(report)
        engine.stop()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func readEnergy() -> (cpu: Double, joules: Double) {
        var info = task_power_info_v2()
        var count = mach_msg_type_number_t(MemoryLayout<task_power_info_v2>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO_V2), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        // I tempi sono in tick del processore, non in nanosecondi.
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticks = Double(info.cpu_energy.total_user + info.cpu_energy.total_system)
        let cpu = ticks * Double(timebase.numer) / Double(timebase.denom) / 1e9
        return (cpu, Double(info.task_energy) / 1e9)
    }

    private static func stateName() -> String {
        switch UIApplication.shared.applicationState {
        case .active: "attiva"
        case .inactive: "inattiva"
        case .background: "background"
        @unknown default: "?"
        }
    }

    private static func save(_ report: Report) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return }
        try? data.write(to: URL.documentsDirectory.appending(path: "bg-check-\(report.scenario).json"), options: .atomic)
    }
}
