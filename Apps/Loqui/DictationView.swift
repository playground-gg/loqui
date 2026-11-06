import LoquiCatalog
import LoquiEngines
import LoquiShared
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class DictationModel {
    enum Phase: Equatable {
        case idle
        case preparing(String)
        case listening
        case transcribing
    }

    private(set) var phase = Phase.idle
    private(set) var segments: [DictatedSegment] = []
    private(set) var errorMessage: String?
    private(set) var footprintMB = 0.0
    /// La dettatura è partita dalla tastiera: il testo va consegnato lì, non mostrato qui.
    private(set) var isFromKeyboard = false

    private let capture = AudioCapture()
    private let sharedStore = SharedStore()
    private var sharedState = SharedState()
    private var store: ModelStore?

    /// Collega i segnali della tastiera. Va chiamato una volta sola, all'avvio.
    func connectKeyboard(store: ModelStore) {
        self.store = store
        clearSharedText()
        DarwinNotifier.shared.observe(.start) { [weak self] in
            Task { @MainActor in self?.startFromKeyboard() }
        }
        DarwinNotifier.shared.observe(.stop) { [weak self] in
            Task { @MainActor in self?.stopFromKeyboard() }
        }
        DarwinNotifier.shared.observe(.delivered) { [weak self] in
            Task { @MainActor in self?.clearSharedText() }
        }
    }

    func startFromKeyboard() {
        guard phase == .idle, let store else { return }
        isFromKeyboard = true
        Task { await start(store: store) }
    }

    private func stopFromKeyboard() {
        guard phase == .listening else { return }
        stopRecording()
    }

    func toggle(store: ModelStore) {
        switch phase {
        case .idle:
            isFromKeyboard = false
            Task { await start(store: store) }
        case .listening: stopRecording()
        case .preparing, .transcribing: break
        }
    }

    func clear() {
        segments = []
        errorMessage = nil
    }

    private func stopRecording() {
        phase = .transcribing
        publish(.transcribing)
        capture.stop()
    }

    private func start(store: ModelStore) async {
        errorMessage = nil
        phase = .preparing("Permesso microfono…")
        guard await AudioCapture.requestPermission() else {
            finish(error: "Permesso negato. Attiva il microfono per Loqui in Impostazioni → Privacy e sicurezza.")
            return
        }
        // Se iOS sospende l'app dopo lo stop, la trascrizione deve comunque arrivare in fondo.
        let background = UIApplication.shared.beginBackgroundTask(withName: "Trascrizione")
        defer { UIApplication.shared.endBackgroundTask(background) }
        do {
            let session = DictationSession { try await store.preparedEngine() }
            // Il microfono parte subito: chi parla mentre il modello si carica non perde nulla.
            let audio = try capture.start()
            phase = .listening
            publish(.listening)
            footprintMB = physicalFootprintMB()
            let result = try await session.run(audio: audio) { [weak self] level in
                Task { @MainActor in self?.publishLevel(level) }
            }
            switch result {
            case .text(let segment):
                if isFromKeyboard {
                    deliverToKeyboard(segment)
                } else {
                    segments.append(segment)
                }
                finish(error: nil)
            case .noText(let seconds, let peak):
                finish(error: Self.noTextMessage(seconds: seconds, peak: peak))
            }
        } catch {
            capture.stop()
            finish(error: error.localizedDescription)
        }
    }

    private func finish(error: String?) {
        errorMessage = error
        footprintMB = physicalFootprintMB()
        phase = .idle
        sharedState.phase = .idle
        sharedState.level = 0
        sharedState.errorMessage = isFromKeyboard ? error : nil
        write()
    }

    private func deliverToKeyboard(_ segment: DictatedSegment) {
        sharedState.pendingText = segment.text
        sharedState.pendingID = segment.id
    }

    private func publish(_ phase: DictationPhase) {
        sharedState.phase = phase
        sharedState.errorMessage = nil
        write()
    }

    private func publishLevel(_ level: Float) {
        guard phase == .listening else { return }
        sharedState.level = level
        write()
    }

    /// Il testo resta nel contenitore condiviso solo finché la tastiera non lo ha inserito.
    private func clearSharedText() {
        sharedState.pendingText = nil
        sharedState.pendingID = nil
        write()
    }

    private func write() {
        sharedState.updatedAt = Date()
        sharedStore.write(sharedState)
        DarwinNotifier.post(.stateChanged)
    }

    private static func noTextMessage(seconds: Double, peak: Float) -> String {
        let duration = String(format: "%.1f s", seconds)
        if seconds < 0.5 { return "Registrazione troppo breve (\(duration)). Tocca Ferma quando hai finito di parlare." }
        if peak == 0 {
            return "iOS ha silenziato il microfono: audio a zero per \(duration). Può succedere se il telefono è controllato dal Mac o il microfono è in uso altrove. Usa il telefono direttamente e riprova."
        }
        if peak < 0.01 {
            return "Il microfono ha captato pochissimo in \(duration) (livello \(String(format: "%.4f", peak))). Parla più vicino al telefono."
        }
        return "Nessun testo riconosciuto in \(duration) di audio. Riprova parlando più vicino al telefono."
    }
}

struct DictationView: View {
    @Bindable var store: ModelStore
    let model: DictationModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Form {
                    if store.myLanguages.count > 1 {
                        LanguagePicker(store: store)
                    }
                    if store.usableModels.isEmpty {
                        Text("Nessun modello pronto per \(store.languageName(store.language)). Scaricane uno nella scheda Modelli.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Modello", selection: $store.activeModelID) {
                            ForEach(store.usableModels) { Text($0.name).tag($0.id) }
                        }
                    }
                }
                .disabled(model.phase != .idle)
                .frame(height: store.myLanguages.count > 1 ? 140 : 90)
                .scrollDisabled(true)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.segments) { segment in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(segment.text).textSelection(.enabled)
                                Text(metrics(for: segment))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }

                if let error = model.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Text(statusText)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    model.toggle(store: store)
                } label: {
                    Label(buttonTitle, systemImage: model.phase == .listening ? "stop.fill" : "mic.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.phase == .listening ? .red : .accentColor)
                .disabled(!isButtonEnabled)
                .padding([.horizontal, .bottom])
            }
            .navigationTitle("Loqui")
            .toolbar {
                Button("Pulisci", action: model.clear)
                    .disabled(model.segments.isEmpty)
            }
        }
    }

    private var isButtonEnabled: Bool {
        switch model.phase {
        case .idle: store.activeModel.map { store.usableModels.contains($0) } ?? false
        case .listening: true
        case .preparing, .transcribing: false
        }
    }

    private var buttonTitle: String {
        model.phase == .listening ? "Ferma" : "Detta"
    }

    private var statusText: String {
        switch model.phase {
        case .idle: store.activeModel?.detectsLanguageAutomatically == true ? "Pronto · lingua riconosciuta in automatico" : "Pronto"
        case .preparing(let message): message
        case .listening where model.isFromKeyboard: "In ascolto: torna all'app dove stavi scrivendo"
        case .listening: String(format: "In ascolto · RAM %.0f MB", model.footprintMB)
        case .transcribing: "Trascrizione…"
        }
    }

    private func metrics(for segment: DictatedSegment) -> String {
        String(format: "stop→testo %.2f s · audio %.1f s", segment.stopToTextSeconds, segment.audioSeconds)
    }
}
