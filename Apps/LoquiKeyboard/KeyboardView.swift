import LoquiShared
import SwiftUI

struct KeyboardView: View {
    let model: KeyboardModel

    var body: some View {
        VStack(spacing: 10) {
            statusArea
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 12)

            micButton

            HStack(spacing: 8) {
                if model.showsGlobe {
                    key(systemImage: "globe", label: "Tastiera successiva", action: model.nextKeyboard)
                }
                key(systemImage: "arrow.uturn.backward", label: "Annulla dettatura", action: model.undo)
                    .disabled(!model.buffer.canUndo)
                Button(action: model.insertSpace) {
                    Text("spazio")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.bordered)
                key(systemImage: "delete.left", label: "Cancella", action: model.deleteBackward)
                key(systemImage: "return", label: "Invio", action: model.insertReturn)
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusArea: some View {
        if let message = model.message {
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        } else if model.phase == .listening {
            Waveform(level: model.level)
        } else if model.phase == .transcribing {
            ProgressView("Trascrizione…").font(.caption)
        } else if let preview = model.preview {
            Text(preview)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.secondary)
        } else {
            Text(model.isWaitingForApp ? "Collegamento a Loqui…" : "Tocca per dettare")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var micButton: some View {
        Button(action: model.tapMic) {
            Label(micTitle, systemImage: model.phase == .listening ? "stop.fill" : "mic.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .tint(model.phase == .listening ? .red : .accentColor)
        .disabled(model.phase == .transcribing)
        .padding(.horizontal, 8)
    }

    private var micTitle: String {
        switch model.phase {
        case .idle: "Detta"
        case .listening: "Ferma"
        case .transcribing: "Attendi"
        }
    }

    private func key(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(minWidth: 34, minHeight: 42)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
    }
}

/// Barre che seguono il livello del microfono, più alte al centro.
private struct Waveform: View {
    let level: Float

    private let weights: [CGFloat] = [0.35, 0.55, 0.8, 1, 0.8, 0.55, 0.35]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(weights.indices, id: \.self) { index in
                Capsule()
                    .fill(.red)
                    .frame(width: 5, height: 6 + 34 * CGFloat(min(level * 4, 1)) * weights[index])
            }
        }
        .animation(.linear(duration: 0.1), value: level)
        .accessibilityLabel("Registrazione in corso")
    }
}
