import Foundation
import LoquiCatalog
import LoquiEngines
import Observation
import UIKit

/// Esegue il benchmark sul dispositivo e conserva i risultati nei Documenti dell'app.
@MainActor
@Observable
final class BenchmarkModel {
    private(set) var runningModelID: String?
    private(set) var status = ""
    private(set) var errorMessage: String?
    private(set) var reports: [BenchmarkReport] = []

    private static var directory: URL {
        URL.documentsDirectory.appending(path: "benchmarks", directoryHint: .isDirectory)
    }

    init() {
        reports = Self.loadReports()
    }

    func latestReport(for model: CatalogModel) -> BenchmarkReport? {
        reports.first { $0.engineID == model.id }
    }

    func run(model: CatalogModel, store: ModelStore) {
        guard runningModelID == nil else { return }
        let clips = Bundle.main.urls(forResourcesWithExtension: "wav", subdirectory: "BenchmarkClips") ?? []
        guard !clips.isEmpty else {
            errorMessage = "Clip mancanti: esegui scripts/generate-benchmark-clips.sh e ricompila."
            return
        }
        runningModelID = model.id
        errorMessage = nil
        status = "Preparazione…"
        UIApplication.shared.isIdleTimerDisabled = true

        Task {
            do {
                // Il motore della dettatura falserebbe la misura della RAM.
                await store.unloadEngine()
                let engine = try EngineFactory.make(model: model, language: store.language)
                let report = try await Benchmark.run(engine: engine, clips: clips) { [weak self] message in
                    Task { @MainActor in self?.status = message }
                }
                try Self.save(report)
                reports.insert(report, at: 0)
                status = ""
            } catch {
                errorMessage = error.localizedDescription
                status = ""
                Self.saveError(error, modelID: model.id)
            }
            runningModelID = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private static func save(_ report: BenchmarkReport) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let name = "\(report.engineID)-\(Int(report.date.timeIntervalSince1970)).json"
        try encoder.encode(report).write(to: directory.appending(path: name), options: .atomic)
    }

    /// Serve a leggere gli errori dal Mac quando il benchmark parte con `--auto-benchmark`.
    private static func saveError(_ error: Error, modelID: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(modelID)-\(Int(Date().timeIntervalSince1970)).error.txt"
        try? String(describing: error).write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
    }

    private static func loadReports() -> [BenchmarkReport] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .compactMap { try? decoder.decode(BenchmarkReport.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }
}
