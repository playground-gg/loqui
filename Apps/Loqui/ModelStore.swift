import Foundation
import LoquiCatalog
import LoquiEngines
import Observation

/// Stato dei modelli: lingua, modello attivo, download, eliminazione e motore caricato.
@MainActor
@Observable
final class ModelStore {
    enum InstallState: Equatable {
        case notInstalled
        case downloading(Double)
        case installed(bytes: Int64?)
    }

    let catalog: Catalog
    private(set) var states: [String: InstallState] = [:]
    private(set) var errorMessage: String?

    /// Lingua usata per la prossima dettatura, sempre tra `myLanguages`.
    var language: String {
        didSet {
            defaults.set(language, forKey: Keys.language)
            Task {
                await refresh()
                selectUsableModelIfNeeded()
            }
        }
    }

    /// Lingue scelte dall'utente, nell'ordine del catalogo. Mai vuoto.
    private(set) var myLanguages: [String] {
        didSet { defaults.set(myLanguages, forKey: Keys.myLanguages) }
    }

    var activeModelID: String {
        didSet { defaults.set(activeModelID, forKey: Keys.activeModel) }
    }

    private let defaults = UserDefaults.standard
    private var completed: Set<String>
    private var loadedEngine: (any TranscriptionEngine)?
    private var loadedKey: String?
    private var loading: (key: String, task: Task<any TranscriptionEngine, Error>)?
    private var downloadTask: Task<Void, Never>?

    private enum Keys {
        static let language = "language"
        static let myLanguages = "myLanguages"
        static let activeModel = "activeModel"
        static let completed = "completedDownloads"
    }

    init() {
        do {
            catalog = try Catalog.bundled()
        } catch {
            fatalError("Catalogo modelli non valido: \(error)")
        }
        let known = Set(catalog.languages.map(\.code))
        let saved = (defaults.stringArray(forKey: Keys.myLanguages) ?? []).filter(known.contains)
        let chosen = saved.isEmpty ? Self.deviceLanguages(known: known) : saved
        let language = defaults.string(forKey: Keys.language).flatMap { chosen.contains($0) ? $0 : nil } ?? chosen[0]
        self.language = language
        myLanguages = chosen
        activeModelID = defaults.string(forKey: Keys.activeModel)
            ?? catalog.recommended(for: language)?.id
            ?? catalog.models[0].id
        completed = Set(defaults.stringArray(forKey: Keys.completed) ?? [])
    }

    /// Le lingue del telefono presenti nel catalogo, così al primo avvio la scelta è già sensata.
    private static func deviceLanguages(known: Set<String>) -> [String] {
        var result: [String] = []
        for identifier in Locale.preferredLanguages {
            if let code = Locale(identifier: identifier).language.languageCode?.identifier,
                known.contains(code), !result.contains(code) {
                result.append(code)
            }
        }
        return result.isEmpty ? ["en"] : result
    }

    func isMine(_ language: String) -> Bool {
        myLanguages.contains(language)
    }

    /// Aggiunge o toglie una lingua. L'ultima rimasta non si può togliere.
    func toggleLanguage(_ code: String) {
        if isMine(code) {
            guard myLanguages.count > 1 else { return }
            myLanguages.removeAll { $0 == code }
            if language == code { language = myLanguages[0] }
        } else {
            let order = catalog.languages.map(\.code)
            myLanguages = order.filter { $0 == code || myLanguages.contains($0) }
        }
    }

    func languageName(_ code: String) -> String {
        catalog.languages.first { $0.code == code }?.name ?? code
    }

    /// Lingue dell'utente che il modello non copre: va detto prima di sceglierlo.
    func missingLanguages(of model: CatalogModel) -> [CatalogLanguage] {
        catalog.unsupportedLanguages(of: model, among: myLanguages)
    }

    /// Modelli pronti per la lingua attiva: gli unici che ha senso proporre per dettare.
    var usableModels: [CatalogModel] {
        models.filter { isInstalled($0) && $0.supports(language) }
    }

    /// Passando a una lingua non coperta dal modello attivo si usa un modello pronto che la copre.
    private func selectUsableModelIfNeeded() {
        guard let active = activeModel, !active.supports(language) || !isInstalled(active),
            let next = usableModels.first
        else { return }
        activeModelID = next.id
    }

    var models: [CatalogModel] { catalog.sortedModels(for: language) }
    var recommendedID: String? { catalog.recommended(for: language)?.id }
    var activeModel: CatalogModel? { catalog.model(id: activeModelID) }
    var installedModels: [CatalogModel] { models.filter { isInstalled($0) } }
    var isDownloading: Bool { downloadTask != nil }

    var totalDiskUsage: Int64 {
        states.values.reduce(0) { total, state in
            if case .installed(let bytes?) = state { return total + bytes }
            return total
        }
    }

    func state(of model: CatalogModel) -> InstallState {
        states[model.id] ?? .notInstalled
    }

    func isInstalled(_ model: CatalogModel) -> Bool {
        if case .installed = state(of: model) { return true }
        return false
    }

    func refresh() async {
        for model in catalog.models {
            if case .downloading = state(of: model) { continue }
            guard let engine = try? EngineFactory.make(model: model, language: language) else { continue }
            // Il segno di completamento evita di scambiare un download interrotto per un modello pronto.
            let finished = model.isManagedByOS || completed.contains(model.id)
            if finished, await engine.isInstalled() {
                states[model.id] = .installed(bytes: await engine.diskUsageBytes())
            } else {
                states[model.id] = .notInstalled
            }
        }
    }

    func download(_ model: CatalogModel) {
        guard downloadTask == nil else { return }
        errorMessage = nil
        states[model.id] = .downloading(0)
        BackgroundWork.shared.begin(id: model.id, title: model.name) { [weak self] in
            self?.downloadTask?.cancel()
        }
        downloadTask = Task {
            do {
                let engine = try EngineFactory.make(model: model, language: language)
                try await engine.download { [weak self] fraction in
                    Task { @MainActor in self?.report(fraction, for: model) }
                }
                try Task.checkCancellation()
                markCompleted(model)
                BackgroundWork.shared.finish(success: true)
            } catch {
                if !(error is CancellationError) {
                    errorMessage = "\(model.name): \(error.localizedDescription)"
                }
                BackgroundWork.shared.finish(success: false)
            }
            downloadTask = nil
            states[model.id] = nil
            await refresh()
        }
    }

    func delete(_ model: CatalogModel) async {
        errorMessage = nil
        if loadedEngine?.model.id == model.id { await unloadEngine() }
        do {
            guard let engine = try? EngineFactory.make(model: model, language: language) else { return }
            try await engine.delete()
            completed.remove(model.id)
            defaults.set(Array(completed), forKey: Keys.completed)
        } catch {
            errorMessage = "\(model.name): \(error.localizedDescription)"
        }
        await refresh()
        selectUsableModelIfNeeded()
    }

    /// Motore attivo pronto all'uso: resta in memoria tra una dettatura e l'altra.
    func preparedEngine() async throws -> any TranscriptionEngine {
        guard let model = activeModel, isInstalled(model), model.supports(language) else {
            throw EngineError.unavailable("Scarica un modello per \(languageName(language)) nella scheda Modelli.")
        }
        // Parakeet riconosce la lingua da solo: ricaricarlo costerebbe oltre 10 s per nulla.
        let key = model.detectsLanguageAutomatically ? model.id : "\(model.id)|\(language)"
        if let loadedEngine, loadedKey == key { return loadedEngine }
        // Il precaricamento all'avvio e il tocco su Detta possono arrivare insieme: si carica una volta sola.
        if let loading, loading.key == key { return try await loading.task.value }

        await unloadEngine()
        let language = language
        let task = Task<any TranscriptionEngine, Error> {
            let engine = try EngineFactory.make(model: model, language: language)
            try await engine.load()
            return engine
        }
        loading = (key, task)
        defer {
            if loading?.key == key { loading = nil }
        }
        let engine = try await task.value
        loadedEngine = engine
        loadedKey = key
        return engine
    }

    /// Tiene pronto il modello attivo, così la prima dettatura non deve aspettarlo.
    func preloadActiveEngine() async {
        _ = try? await preparedEngine()
    }

    func unloadEngine() async {
        await loadedEngine?.unload()
        loadedEngine = nil
        loadedKey = nil
    }

    private func report(_ fraction: Double, for model: CatalogModel) {
        guard case .downloading = state(of: model) else { return }
        states[model.id] = .downloading(fraction)
        BackgroundWork.shared.update(fraction)
    }

    private func markCompleted(_ model: CatalogModel) {
        completed.insert(model.id)
        defaults.set(Array(completed), forKey: Keys.completed)
    }
}
