import LoquiCatalog
import LoquiEngines
import SwiftUI

struct ModelsView: View {
    @Bindable var store: ModelStore
    let benchmark: BenchmarkModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        LanguagesView(store: store)
                    } label: {
                        LabeledContent(
                            "Le mie lingue",
                            value: store.myLanguages.map(store.languageName).joined(separator: ", ")
                        )
                    }
                    if store.myLanguages.count > 1 {
                        LanguagePicker(store: store)
                    }
                } footer: {
                    Text("Badge rispetto al modello consigliato per questa lingua. Accuratezza: \(store.catalog.werSource.name). Velocità: \(store.catalog.referenceDevice).")
                }

                if let error = store.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }

                Section {
                    ForEach(store.models) { model in
                        NavigationLink {
                            ModelDetailView(store: store, benchmark: benchmark, model: model)
                        } label: {
                            ModelRow(store: store, model: model)
                        }
                    }
                } footer: {
                    Text("Spazio occupato: \(formatBytes(store.totalDiskUsage))")
                }
            }
            .navigationTitle("Modelli")
            .task { await store.refresh() }
        }
    }
}

/// Scelta della lingua attiva tra quelle dell'utente.
struct LanguagePicker: View {
    @Bindable var store: ModelStore

    var body: some View {
        Picker("Lingua attiva", selection: $store.language) {
            ForEach(store.myLanguages, id: \.self) { Text(store.languageName($0)).tag($0) }
        }
    }
}

private struct LanguagesView: View {
    let store: ModelStore

    var body: some View {
        List {
            Section {
                ForEach(store.catalog.languages) { language in
                    Button {
                        store.toggleLanguage(language.code)
                    } label: {
                        HStack {
                            Text(language.name).foregroundStyle(.primary)
                            Spacer()
                            if store.isMine(language.code) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityAddTraits(store.isMine(language.code) ? .isSelected : [])
                }
            } footer: {
                Text("Scegli tutte le lingue in cui detti. Ne resta sempre almeno una.")
            }
        }
        .navigationTitle("Le mie lingue")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ModelRow: View {
    let store: ModelStore
    let model: CatalogModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if store.activeModelID == model.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Attivo")
                }
                Text(model.name).font(.headline)
                if store.recommendedID == model.id {
                    Text("Consigliato")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.2), in: Capsule())
                }
            }
            BadgeRow(badges: store.catalog.badges(for: model, language: store.language))
            InstallLabel(state: store.state(of: model), model: model)
            let missing = store.missingLanguages(of: model)
            if !missing.isEmpty {
                Text("Non supporta: \(missing.map(\.name).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct BadgeRow: View {
    let badges: ModelBadges

    var body: some View {
        HStack(spacing: 12) {
            badge("Accuratezza", badges.accuracy)
            badge("Velocità", badges.speed)
            badge("Peso", badges.size)
        }
        .font(.caption)
    }

    private func badge(_ title: String, _ level: BadgeLevel) -> some View {
        HStack(spacing: 3) {
            Text(title).foregroundStyle(.secondary)
            Text(level.symbol)
                .fontWeight(.semibold)
                .foregroundStyle(color(level))
        }
        .accessibilityElement(children: .combine)
    }

    private func color(_ level: BadgeLevel) -> Color {
        switch level {
        case .better, .muchBetter: .green
        case .worse, .muchWorse: .orange
        case .same, .unknown: .secondary
        }
    }
}

private struct InstallLabel: View {
    let state: ModelStore.InstallState
    let model: CatalogModel

    var body: some View {
        switch state {
        case .notInstalled:
            Text(model.isManagedByOS ? "Da installare, gestito da iOS" : "Non scaricato · \(model.downloadMB) MB")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .downloading(let fraction):
            ProgressView(value: fraction)
        case .installed(let bytes):
            Text(bytes.map { "Scaricato · \(formatBytes($0))" } ?? "Installato, gestito da iOS")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ModelDetailView: View {
    let store: ModelStore
    let benchmark: BenchmarkModel
    let model: CatalogModel

    var body: some View {
        List {
            actionsSection
            aboutSection
            benchmarkSection
        }
        .navigationTitle(model.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            switch store.state(of: model) {
            case .notInstalled:
                Button(model.isManagedByOS ? "Installa per \(store.languageName(store.language))" : "Scarica (\(model.downloadMB) MB)") {
                    store.download(model)
                }
                .disabled(store.isDownloading || (model.isManagedByOS && !model.supports(store.language)))
            case .downloading(let fraction):
                ProgressView("Download e preparazione", value: fraction)
            case .installed:
                if store.activeModelID == model.id {
                    Label("Modello attivo", systemImage: "checkmark.circle.fill")
                } else if model.supports(store.language) {
                    Button("Usa questo modello") { store.activeModelID = model.id }
                } else {
                    Text("Non supporta \(store.languageName(store.language))").foregroundStyle(.secondary)
                }
                Button(model.isManagedByOS ? "Rilascia" : "Elimina", role: .destructive) {
                    Task { await store.delete(model) }
                }
            }
        } footer: {
            if model.isManagedByOS, store.isInstalled(model) {
                Text("Loqui rilascia il modello: sarà iOS a decidere quando toglierlo.")
            }
        }
    }

    private var aboutSection: some View {
        Section("Scheda") {
            LabeledContent("WER", value: model.wer[store.language].map { String(format: "%.2f%%", $0) } ?? "Non valutato")
            LabeledContent("Lingue", value: model.detectsLanguageAutomatically ? "\(model.languages.count), riconosciute da sole" : "\(model.languages.count)")
            LabeledContent("Download", value: model.isManagedByOS ? "Gestito da iOS" : "\(model.downloadMB) MB")
            LabeledContent("RAM di riferimento", value: model.referenceRAMMB.map { "\($0) MB" } ?? "Da misurare")
            LabeledContent("Velocità di riferimento", value: model.referenceRTFx.map { "\(Int($0))× tempo reale" } ?? "Da misurare")
            LabeledContent("Vocabolario", value: vocabularyLabel)
            LabeledContent("Licenza", value: model.license)
            Text(model.vocabulary.how).font(.footnote).foregroundStyle(.secondary)
            Text(model.notes).font(.footnote)
            if model.wer[store.language] != nil {
                Text("WER: \(store.catalog.werSource.name), \(store.catalog.werSource.dataset).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var vocabularyLabel: String {
        switch model.vocabulary.support {
        case "yes": "Sì"
        case "no": "No"
        default: "Da verificare"
        }
    }

    @ViewBuilder
    private var benchmarkSection: some View {
        Section {
            Button(benchmark.runningModelID == model.id ? "In corso…" : "Benchmark sul mio iPhone") {
                benchmark.run(model: model, store: store)
            }
            .disabled(benchmark.runningModelID != nil || !store.isInstalled(model))

            if benchmark.runningModelID == model.id {
                Text(benchmark.status).foregroundStyle(.secondary)
            }
            if let error = benchmark.errorMessage {
                Text(error).foregroundStyle(.red)
            }
            if let report = benchmark.latestReport(for: model) {
                LabeledContent("Velocità misurata", value: "\(Int(report.overallRTFx))× tempo reale")
                LabeledContent("Velocità pubblicata", value: model.published ?? "Non pubblicata")
                LabeledContent("RAM a modello caricato", value: formatMB(report.footprintLoadedMB))
                LabeledContent("RAM di picco", value: formatMB(report.footprintPeakMB))
                LabeledContent("Primo caricamento", value: formatSeconds(report.firstLoadSeconds))
                ForEach(report.clips) { clip in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(clip.clip): \(formatSeconds(clip.medianInferenceSeconds)) su \(formatSeconds(clip.audioSeconds)) di audio")
                            .font(.caption.monospacedDigit())
                        Text(clip.text).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(report.placement) { placement in
                    LabeledContent(
                        placement.model,
                        value: String(
                            format: "ANE %.0f%% · GPU %.0f%% · CPU %.0f%%",
                            placement.neuralEnginePercent,
                            placement.gpuPercent,
                            placement.cpuPercent
                        )
                    )
                    .font(.caption)
                }
            }
        } header: {
            Text("Misure sul dispositivo")
        } footer: {
            Text("Clip fisse con voce sintetica: misura velocità e RAM, non accuratezza. Tieni l'app aperta durante la prova.")
        }
    }
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private func formatMB(_ value: Double) -> String { String(format: "%.0f MB", value) }
private func formatSeconds(_ value: Double) -> String { String(format: "%.2f s", value) }
