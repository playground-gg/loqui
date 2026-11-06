import Foundation

public enum EngineKind: String, Codable, Sendable {
    case apple, fluidaudio, whisperkit
}

public struct CatalogLanguage: Codable, Sendable, Hashable, Identifiable {
    public var id: String { code }
    public let code: String
    public let name: String
}

public struct VocabularySupport: Codable, Sendable, Hashable {
    public let support: String
    public let how: String
}

public struct CatalogModel: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let engine: EngineKind
    /// Nome del modello per il motore: versione FluidAudio o variante WhisperKit.
    public let engineModel: String
    public let downloadMB: Int
    /// Misurati sul dispositivo di riferimento, nil finché non lo sono.
    public let referenceRAMMB: Int?
    public let referenceRTFx: Double?
    public let published: String?
    public let license: String
    /// Codici delle lingue supportate.
    public let languages: [String]
    /// WER percentuale per codice lingua.
    public let wer: [String: Double]
    public let vocabulary: VocabularySupport
    public let notes: String

    public var isManagedByOS: Bool { engine == .apple }
    /// Parakeet riconosce la lingua da solo: cambiarla non richiede di ricaricare il modello.
    public var detectsLanguageAutomatically: Bool { engine == .fluidaudio }

    public func supports(_ language: String) -> Bool {
        languages.contains(language)
    }
}

public struct WERSource: Codable, Sendable, Hashable {
    public let name: String
    public let dataset: String
    public let url: String
}

public enum BadgeLevel: Sendable, Hashable {
    case muchWorse, worse, same, better, muchBetter, unknown

    public var symbol: String {
        switch self {
        case .muchWorse: "−−"
        case .worse: "−"
        case .same: "="
        case .better: "+"
        case .muchBetter: "++"
        case .unknown: "?"
        }
    }

    /// `ratio` > 1 significa meglio del riferimento.
    init(ratio: Double) {
        switch ratio {
        case 2...: self = .muchBetter
        case 1.2..<2: self = .better
        case 0.8..<1.2: self = .same
        case 0.5..<0.8: self = .worse
        default: self = .muchWorse
        }
    }
}

public struct ModelBadges: Sendable, Hashable {
    public let accuracy: BadgeLevel
    public let speed: BadgeLevel
    public let size: BadgeLevel
}

public struct Catalog: Codable, Sendable {
    public let languages: [CatalogLanguage]
    public let werSource: WERSource
    public let referenceDevice: String
    public let models: [CatalogModel]

    /// Scarto di WER entro cui un modello conta come ugualmente accurato.
    static let accuracyTolerance = 0.10

    public static func bundled() throws -> Catalog {
        guard let url = Bundle.module.url(forResource: "models", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    public func model(id: String) -> CatalogModel? {
        models.first { $0.id == id }
    }

    /// Tra i modelli vicini al miglior WER vince il più veloce: a parità di errori conta la latenza.
    public func recommended(for language: String) -> CatalogModel? {
        let rated = models.filter { $0.supports(language) && $0.wer[language] != nil }
        guard let best = rated.compactMap({ $0.wer[language] }).min() else { return nil }
        return rated
            .filter { $0.wer[language]! <= best * (1 + Self.accuracyTolerance) }
            .max { lhs, rhs in
                let left = lhs.referenceRTFx ?? 0
                let right = rhs.referenceRTFx ?? 0
                return left == right ? lhs.wer[language]! > rhs.wer[language]! : left < right
            }
    }

    /// Consigliato per primo, poi per WER crescente; in fondo i modelli senza WER e quelli senza la lingua.
    public func sortedModels(for language: String) -> [CatalogModel] {
        let recommendedID = recommended(for: language)?.id
        return models.sorted { lhs, rhs in
            if lhs.id == recommendedID { return true }
            if rhs.id == recommendedID { return false }
            if lhs.supports(language) != rhs.supports(language) { return lhs.supports(language) }
            return (lhs.wer[language] ?? .infinity) < (rhs.wer[language] ?? .infinity)
        }
    }

    /// Lingue dell'utente che il modello non supporta, nell'ordine ricevuto.
    public func unsupportedLanguages(of model: CatalogModel, among languages: [String]) -> [CatalogLanguage] {
        languages
            .filter { !model.supports($0) }
            .compactMap { code in self.languages.first { $0.code == code } }
    }

    /// Badge relativi al consigliato per la lingua. Ogni simbolo dice se il modello è meglio o peggio.
    public func badges(for model: CatalogModel, language: String) -> ModelBadges {
        guard let reference = recommended(for: language) else {
            return ModelBadges(accuracy: .unknown, speed: .unknown, size: .unknown)
        }
        return ModelBadges(
            accuracy: Self.lowerIsBetter(model.wer[language], reference.wer[language]),
            speed: Self.higherIsBetter(model.referenceRTFx, reference.referenceRTFx),
            size: Self.lowerIsBetter(Double(model.downloadMB), Double(reference.downloadMB))
        )
    }

    private static func higherIsBetter(_ value: Double?, _ reference: Double?) -> BadgeLevel {
        guard let value, let reference, reference > 0 else { return .unknown }
        return BadgeLevel(ratio: value / reference)
    }

    private static func lowerIsBetter(_ value: Double?, _ reference: Double?) -> BadgeLevel {
        guard let value, let reference else { return .unknown }
        if value == 0 { return reference == 0 ? .same : .muchBetter }
        return BadgeLevel(ratio: reference / value)
    }
}
