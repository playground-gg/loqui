import Foundation
import LoquiEngines
import LoquiShared
import UIKit

/// Prova lanciata dal Mac: batteria con il microfono pronto e il modello in memoria, come tra due dettature.
/// Registro in `Documents/battery-check.json`, aggiornato ogni minuto. Si ferma ricollegando il telefono.
@MainActor
enum BatteryCheck {
    struct Sample: Codable {
        let minutes: Double
        let level: Float
        let state: String
        let thermal: String
        let micOn: Bool
        let footprintMB: Double
    }

    static func run(store: ModelStore) async {
        UIDevice.current.isBatteryMonitoringEnabled = true
        store.activeModelID = "parakeet-ultra"
        await store.preloadActiveEngine()

        let capture = AudioCapture()
        guard (try? capture.start()) != nil else { return }
        capture.stopCollecting()

        let start = Date()
        var samples: [Sample] = []
        var wasUnplugged = false
        while true {
            let state = UIDevice.current.batteryState
            if state == .unplugged { wasUnplugged = true }
            samples.append(Sample(
                minutes: Date().timeIntervalSince(start) / 60,
                level: UIDevice.current.batteryLevel,
                state: name(of: state),
                thermal: name(of: ProcessInfo.processInfo.thermalState),
                micOn: capture.isHot,
                footprintMB: physicalFootprintMB()
            ))
            save(samples)
            if wasUnplugged, state != .unplugged { break }
            try? await Task.sleep(for: .seconds(60))
        }
        capture.release()
    }

    private static func name(of state: UIDevice.BatteryState) -> String {
        switch state {
        case .charging: "in carica"
        case .full: "piena"
        case .unplugged: "scollegato"
        default: "?"
        }
    }

    private static func name(of state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "?"
        }
    }

    private static func save(_ samples: [Sample]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(samples) else { return }
        try? data.write(to: URL.documentsDirectory.appending(path: "battery-check.json"), options: .atomic)
    }
}
