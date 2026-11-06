import Foundation

public enum LoquiIPC {
    public static let appGroup = "group.com.giovannigiofre.loqui"
    public static let dictateURL = URL(string: "loqui://dictate")!

    /// Notifiche Darwin: non portano dati, avvisano solo che qualcosa è cambiato.
    public enum Signal: String, CaseIterable, Sendable {
        case start = "com.giovannigiofre.loqui.ipc.start"
        case stop = "com.giovannigiofre.loqui.ipc.stop"
        case cancel = "com.giovannigiofre.loqui.ipc.cancel"
        /// La tastiera ha inserito il testo: l'app può cancellarlo dal contenitore condiviso.
        case delivered = "com.giovannigiofre.loqui.ipc.delivered"
        case stateChanged = "com.giovannigiofre.loqui.ipc.state"
    }
}

public enum DictationPhase: String, Codable, Sendable {
    case idle, listening, transcribing
}

/// Stato condiviso tra app e tastiera. Scrive solo l'app, legge la tastiera.
public struct SharedState: Codable, Sendable, Equatable {
    public var phase: DictationPhase
    /// Livello del microfono da 0 a 1, per la waveform.
    public var level: Float
    public var pendingText: String?
    public var pendingID: UUID?
    public var errorMessage: String?
    public var updatedAt: Date

    public init(
        phase: DictationPhase = .idle,
        level: Float = 0,
        pendingText: String? = nil,
        pendingID: UUID? = nil,
        errorMessage: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.phase = phase
        self.level = level
        self.pendingText = pendingText
        self.pendingID = pendingID
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
    }

    /// Mentre registra l'app aggiorna il livello di continuo: uno stato fermo vuol dire app chiusa da iOS.
    public func isAlive(now: Date = Date()) -> Bool {
        switch phase {
        case .idle: true
        case .listening: now.timeIntervalSince(updatedAt) < 3
        case .transcribing: now.timeIntervalSince(updatedAt) < 60
        }
    }

    /// Un testo vecchio non va inserito: l'utente può essere passato a un altro campo o a un'altra app.
    public func deliverableText(now: Date = Date()) -> (id: UUID, text: String)? {
        guard let pendingID, let pendingText, now.timeIntervalSince(updatedAt) < 120 else { return nil }
        return (pendingID, pendingText)
    }
}

/// File nel contenitore dell'App Group. Senza Accesso completo la tastiera non può usarlo.
public struct SharedStore: Sendable {
    private let fileURL: URL?

    public init(appGroup: String = LoquiIPC.appGroup) {
        fileURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "state.json")
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public var isAvailable: Bool { fileURL != nil }

    public func read() -> SharedState? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? Self.decoder.decode(SharedState.self, from: data)
    }

    public func write(_ state: SharedState) {
        guard let fileURL, let data = try? Self.encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
