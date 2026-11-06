import BackgroundTasks
import Foundation

/// Tiene viva l'app durante un download iniziato in primo piano, con l'avanzamento mostrato da iOS.
/// Non copre la chiusura forzata dell'app: in quel caso il download va ripreso a mano.
@MainActor
final class BackgroundWork {
    static let shared = BackgroundWork()
    private static let prefix = "com.giovannigiofre.loqui.download"

    private var registered: Set<String> = []
    private var task: BGContinuedProcessingTask?
    private var fraction = 0.0
    private var outcome: Bool?
    private var onExpiration: (() -> Void)?

    /// iOS vuole un gestore per l'identificativo completo prima della richiesta, e uno solo per identificativo.
    private func registerIfNeeded(_ identifier: String) {
        guard registered.insert(identifier).inserted else { return }
        Self.register(identifier)
    }

    /// `nonisolated`: iOS chiama il gestore su una sua coda, non sul main actor.
    private nonisolated static func register(_ identifier: String) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            nonisolated(unsafe) let unsafeTask = task
            task.expirationHandler = {
                Task { @MainActor in BackgroundWork.shared.expire() }
            }
            Task { @MainActor in BackgroundWork.shared.attach(unsafeTask) }
        }
    }

    /// Se iOS rifiuta la richiesta il download prosegue comunque, ma solo in primo piano.
    func begin(id: String, title: String, onExpiration: @escaping () -> Void) {
        task = nil
        fraction = 0
        outcome = nil
        self.onExpiration = onExpiration
        let identifier = "\(Self.prefix).\(id)"
        registerIfNeeded(identifier)
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: title,
            subtitle: "Download del modello"
        )
        request.strategy = .queue
        try? BGTaskScheduler.shared.submit(request)
    }

    func update(_ fraction: Double) {
        self.fraction = fraction
        task?.progress.completedUnitCount = Int64(fraction * 100)
    }

    func finish(success: Bool) {
        outcome = success
        onExpiration = nil
        task?.setTaskCompleted(success: success)
        task = nil
    }

    private func attach(_ task: BGContinuedProcessingTask) {
        // Il download può finire prima che iOS avvii il task.
        if let outcome {
            task.setTaskCompleted(success: outcome)
            return
        }
        task.progress.totalUnitCount = 100
        task.progress.completedUnitCount = Int64(fraction * 100)
        self.task = task
    }

    private func expire() {
        onExpiration?()
        finish(success: false)
    }
}
