#if os(iOS)
@preconcurrency import AVFoundation
import Foundation
import Synchronization

/// Cattura il microfono e consegna blocchi a 16 kHz mono. L'audio non viene mai scritto su disco.
///
/// Il microfono può restare acceso tra una dettatura e l'altra: iOS non permette di riaccenderlo dal
/// background, ma con il motore già attivo basta aprire il flusso. Finché il flusso è chiuso i campioni
/// vengono scartati senza convertirli né conservarli.
@MainActor
public final class AudioCapture {
    private let engine = AVAudioEngine()
    private let gate = StreamGate()

    public init() {}

    /// Il microfono è acceso, quindi la prossima dettatura può partire anche dal background.
    public var isHot: Bool { engine.isRunning }

    public static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    public func start() throws -> AsyncStream<[Float]> {
        if !engine.isRunning { try startEngine() }
        let (stream, continuation) = AsyncStream.makeStream(of: [Float].self, bufferingPolicy: .unbounded)
        gate.open(continuation)
        return stream
    }

    /// Chiude la dettatura in corso e lascia il microfono acceso.
    public func stopCollecting() {
        gate.close()
    }

    /// Spegne il microfono e libera la sessione audio: da qui iOS può sospendere l'app.
    public func release() {
        gate.close()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startEngine() throws {
        let session = AVAudioSession.sharedInstance()
        // `.measurement` disattiva la regolazione del guadagno: su iPhone il livello risultava circa 10 volte più basso.
        try session.setCategory(.record, mode: .default)
        try session.setPreferredSampleRate(Double(loquiSampleRate))
        try session.setActive(true)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(loquiSampleRate),
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: target) else {
            throw EngineError.unavailable("Formato del microfono non supportato.")
        }

        // iOS può fermare il motore da solo, per esempio con una telefonata: il vecchio tap va tolto.
        input.removeTap(onBus: 0)
        let tap = Self.makeTap(converter: converter, target: target, gate: gate)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat, block: tap)
        engine.prepare()
        try engine.start()
    }

    /// `nonisolated`: il blocco gira sul thread audio, non sul main actor.
    private nonisolated static func makeTap(
        converter: AVAudioConverter,
        target: AVAudioFormat,
        gate: StreamGate
    ) -> AVAudioNodeTapBlock {
        return { buffer, _ in
            guard gate.isOpen else { return }
            let ratio = target.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            nonisolated(unsafe) var delivered = false
            nonisolated(unsafe) let source = buffer
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if delivered {
                    status.pointee = .noDataNow
                    return nil
                }
                delivered = true
                status.pointee = .haveData
                return source
            }
            guard error == nil, let channel = output.floatChannelData?[0], output.frameLength > 0 else { return }
            gate.yield(Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength))))
        }
    }
}

/// Passaggio tra il thread audio e la dettatura in corso.
private final class StreamGate: Sendable {
    private let continuation = Mutex<AsyncStream<[Float]>.Continuation?>(nil)

    var isOpen: Bool { continuation.withLock { $0 != nil } }

    func open(_ new: AsyncStream<[Float]>.Continuation) {
        continuation.withLock { current in
            current?.finish()
            current = new
        }
    }

    func close() {
        continuation.withLock { current in
            current?.finish()
            current = nil
        }
    }

    func yield(_ samples: [Float]) {
        continuation.withLock { _ = $0?.yield(samples) }
    }
}
#endif
