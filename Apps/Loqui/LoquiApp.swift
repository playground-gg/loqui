import LoquiEngines
import LoquiShared
import SwiftUI

@main
struct LoquiApp: App {
    @State private var store = ModelStore()
    @State private var benchmark = BenchmarkModel()
    @State private var dictation = DictationModel()
    @State private var tab = Tab.dictation

    private enum Tab { case dictation, models }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                DictationView(store: store, model: dictation)
                    .tabItem { Label("Dettatura", systemImage: "mic") }
                    .tag(Tab.dictation)
                ModelsView(store: store, benchmark: benchmark)
                    .tabItem { Label("Modelli", systemImage: "square.stack.3d.up") }
                    .tag(Tab.models)
            }
            .onOpenURL { url in
                guard url == LoquiIPC.dictateURL else { return }
                tab = .dictation
                dictation.startFromKeyboard()
            }
            .task {
                // La prova del contenitore deve vedere lo stato com'è, prima che l'app lo riscriva.
                if CommandLine.arguments.contains("--auto-group-check") { GroupCheck.run() }
                dictation.connectKeyboard(store: store)
                await store.refresh()
                if CommandLine.arguments.contains(where: { $0.hasPrefix("--auto-") }) {
                    await runRequestedAutomation()
                } else {
                    await store.preloadActiveEngine()
                }
            }
        }
    }

    /// `--auto-install <id>`, `--auto-benchmark <id>`, `--auto-language-check` e `--auto-mixed-check` ripetono le prove dal Mac.
    private func runRequestedAutomation() async {
        let arguments = CommandLine.arguments
        func value(of flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        if let id = value(of: "--auto-install"), let model = store.catalog.model(id: id) {
            tab = .models
            store.download(model)
        }
        if let id = value(of: "--auto-benchmark"), let model = store.catalog.model(id: id) {
            tab = .models
            benchmark.run(model: model, store: store)
        }
        if arguments.contains("--auto-language-check") {
            await LanguageCheck.run(catalog: store.catalog)
        }
        if let scenario = value(of: "--auto-bg-check") {
            await BackgroundCheck.run(scenario: scenario, store: store)
        }
        if arguments.contains("--auto-battery-check") {
            await BatteryCheck.run(store: store)
        }
        if arguments.contains("--auto-mixed-check") {
            await LanguageCheck.runMixed(catalog: store.catalog)
        }
    }
}
