import Foundation
import LoquiShared
import Observation
import UIKit

@MainActor
@Observable
final class KeyboardModel {
    private(set) var phase = DictationPhase.idle
    private(set) var level: Float = 0
    private(set) var message: String?
    private(set) var preview: String?
    private(set) var isWaitingForApp = false
    var showsGlobe = true

    private weak var controller: UIInputViewController?
    private let store = SharedStore()
    private var lastDeliveredID: UUID?
    private var waitTask: Task<Void, Never>?
    private var lastFinishedAt: Date?

    /// Evita di ripartire subito se la tastiera ricompare appena dopo una dettatura.
    private static let autoStartCooldown: TimeInterval = 2

    init(controller: UIInputViewController) {
        self.controller = controller
        DarwinNotifier.shared.observe(.stateChanged) { [weak self] in
            Task { @MainActor in self?.syncState() }
        }
    }

    /// Senza Accesso completo iOS non dà accesso al contenitore condiviso.
    var canDictate: Bool {
        (controller?.hasFullAccess ?? false) && store.isAvailable
    }

    func didAppear() {
        showsGlobe = controller?.needsInputModeSwitchKey ?? true
        saveMemoryMeasure()
        syncState()
    }

    /// Scegliere Loqui dal globo vuol dire voler dettare: la dettatura parte senza toccare nulla.
    func autoStartIfNeeded() {
        guard phase == .idle, canDictate else { return }
        if let lastFinishedAt, Date().timeIntervalSince(lastFinishedAt) < Self.autoStartCooldown { return }
        message = nil
        requestStart()
    }

    func tapMic() {
        message = nil
        guard canDictate else {
            message = "Attiva Accesso completo: Impostazioni → Generali → Tastiera → Tastiere → Loqui."
            return
        }
        switch phase {
        case .idle: requestStart()
        case .listening: DarwinNotifier.post(.stop)
        case .transcribing: break
        }
    }

    /// Scarta la dettatura e torna alla tastiera di prima: serve anche se è partita senza volerlo.
    func cancelDictation() {
        waitTask?.cancel()
        isWaitingForApp = false
        DarwinNotifier.post(.cancel)
        lastFinishedAt = Date()
        controller?.advanceToNextInputMode()
    }

    func deleteBackward() { controller?.textDocumentProxy.deleteBackward() }
    func nextKeyboard() { controller?.advanceToNextInputMode() }

    /// Se l'app è viva risponde alla notifica; altrimenti va aperta.
    private func requestStart() {
        isWaitingForApp = true
        DarwinNotifier.post(.start)
        waitTask?.cancel()
        waitTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.openAppIfNeeded()
        }
    }

    private func openAppIfNeeded() {
        guard phase == .idle else { return }
        isWaitingForApp = false
        controller?.extensionContext?.open(LoquiIPC.dictateURL) { [weak self] opened in
            guard !opened else { return }
            Task { @MainActor in self?.openThroughResponderChain() }
        }
    }

    /// iOS può rifiutare `extensionContext.open` a una tastiera. Vedi rischio 1 in PLAN.md.
    private func openThroughResponderChain() {
        var responder: UIResponder? = controller
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        while let current = responder {
            if let application = current as? UIApplication, application.responds(to: selector) {
                application.open(LoquiIPC.dictateURL, options: [:]) { [weak self] opened in
                    guard !opened else { return }
                    Task { @MainActor in self?.showOpenAppHint() }
                }
                return
            }
            responder = current.next
        }
        showOpenAppHint()
    }

    private func showOpenAppHint() {
        message = "Apri Loqui, tocca Detta e torna qui: la dettatura finirà in questo campo."
    }

    private func syncState() {
        guard let state = store.read() else { return }
        let previous = phase
        phase = state.isAlive() ? state.phase : .idle
        if previous != .idle, phase == .idle { lastFinishedAt = Date() }
        level = phase == .listening ? state.level : 0
        if phase != .idle {
            isWaitingForApp = false
            waitTask?.cancel()
            message = nil
        }
        if let error = state.errorMessage, phase == .idle { message = error }
        deliverIfNeeded(state)
    }

    private func deliverIfNeeded(_ state: SharedState) {
        guard let (id, text) = state.deliverableText(), id != lastDeliveredID,
            let proxy = controller?.textDocumentProxy
        else { return }
        lastDeliveredID = id
        let inserted = DictationBuffer.textToInsert(text, after: proxy.documentContextBeforeInput)
        proxy.insertText(inserted)
        preview = text
        lastFinishedAt = Date()
        DarwinNotifier.post(.delivered)
        // La tastiera di Loqui serve solo a dettare: finito, si torna subito a quella abituale.
        controller?.advanceToNextInputMode()
    }

    /// Misura per l'obiettivo sotto i 40 MB, leggibile dal Mac nel contenitore condiviso.
    private func saveMemoryMeasure() {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: LoquiIPC.appGroup) else {
            return
        }
        let line = String(format: "%.1f", physicalFootprintMB())
        try? line.write(to: directory.appending(path: "keyboard-footprint-mb.txt"), atomically: true, encoding: .utf8)
    }
}
