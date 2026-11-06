import Foundation
import LoquiShared

/// Prova lanciata dal Mac: cosa vede l'app nel contenitore condiviso. Risultato in `Documents/group-check.json`.
enum GroupCheck {
    struct Report: Codable {
        let containerPath: String?
        let files: [String]
        let keyboardFootprintMB: String?
        let phase: String?
        let hasPendingText: Bool
        let stateAgeSeconds: Double?
    }

    static func run() {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: LoquiIPC.appGroup)
        let files = container.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
        let footprint = container.flatMap {
            try? String(contentsOf: $0.appending(path: "keyboard-footprint-mb.txt"), encoding: .utf8)
        }
        let state = SharedStore().read()
        let report = Report(
            containerPath: container?.path,
            files: files,
            keyboardFootprintMB: footprint,
            phase: state?.phase.rawValue,
            hasPendingText: state?.pendingText != nil,
            stateAgeSeconds: state.map { Date().timeIntervalSince($0.updatedAt) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report) {
            try? data.write(to: URL.documentsDirectory.appending(path: "group-check.json"), options: .atomic)
        }
    }
}
