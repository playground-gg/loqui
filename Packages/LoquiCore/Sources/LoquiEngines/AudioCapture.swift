#if os(iOS)
@preconcurrency import AVFoundation
import Foundation

/// Cattura il microfono e consegna blocchi a 16 kHz mono. L'audio non viene mai scritto su disco.
@MainActor
public final class AudioCapture {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<[Float]>.Continuation?

    public init() {}

    public static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    public func start() throws -> AsyncStream<[Float]> {
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

        let (stream, continuation) = AsyncStream.makeStream(of: [Float].self, bufferingPolicy: .unbounded)
        self.continuation = continuation
        let tap = Self.makeTap(converter: converter, target: target, continuation: continuation)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat, block: tap)
        engine.prepare()
        try engine.start()
        return stream
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// `nonisolated`: il blocco gira sul thread audio, non sul main actor.
    private nonisolated static func makeTap(
        converter: AVAudioConverter,
        target: AVAudioFormat,
        continuation: AsyncStream<[Float]>.Continuation
    ) -> AVAudioNodeTapBlock {
        return { buffer, _ in
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
            continuation.yield(Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength))))
        }
    }
}
#endif
