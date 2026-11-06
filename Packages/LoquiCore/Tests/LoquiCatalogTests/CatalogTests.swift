import Testing
@testable import LoquiCatalog

@Suite struct CatalogTests {
    private func catalog() throws -> Catalog { try Catalog.bundled() }

    @Test func bundledCatalogListsTheV1Models() throws {
        let ids = Set(try catalog().models.map(\.id))
        #expect(ids == ["parakeet-ultra", "parakeet-tdt-v3", "whisper-large-v3-turbo", "whisper-small", "apple-speechanalyzer"])
    }

    @Test func everyRatedLanguageIsDeclared() throws {
        let catalog = try catalog()
        let codes = Set(catalog.languages.map(\.code))
        for model in catalog.models {
            #expect(Set(model.languages).isSubset(of: codes), "\(model.id)")
            #expect(Set(model.wer.keys).isSubset(of: Set(model.languages)), "\(model.id)")
        }
    }

    @Test func italianRecommendsParakeetUltra() throws {
        #expect(try catalog().recommended(for: "it")?.id == "parakeet-ultra")
    }

    /// In tedesco turbo ha il WER minimo di poco, ma Ultra è nella tolleranza ed è misurato più veloce.
    @Test func nearlyEquivalentAccuracyPrefersTheFasterModel() throws {
        #expect(try catalog().recommended(for: "de")?.id == "parakeet-ultra")
    }

    @Test func unknownLanguageHasNoRecommendationAndUnknownBadges() throws {
        let catalog = try catalog()
        #expect(catalog.recommended(for: "xx") == nil)
        let badges = catalog.badges(for: catalog.models[0], language: "xx")
        #expect(badges == ModelBadges(accuracy: .unknown, speed: .unknown, size: .unknown))
    }

    @Test func recommendedModelIsFirstAndUnratedLast() throws {
        let sorted = try catalog().sortedModels(for: "it")
        #expect(sorted.first?.id == "parakeet-ultra")
        #expect(sorted.last?.id == "apple-speechanalyzer")
    }

    @Test func badgesAreRelativeToTheRecommendedModel() throws {
        let catalog = try catalog()
        let ultra = try #require(catalog.model(id: "parakeet-ultra"))
        let small = try #require(catalog.model(id: "whisper-small"))
        let apple = try #require(catalog.model(id: "apple-speechanalyzer"))

        #expect(catalog.badges(for: ultra, language: "it") == ModelBadges(accuracy: .same, speed: .same, size: .same))

        let smallBadges = catalog.badges(for: small, language: "it")
        #expect(smallBadges.accuracy == .muchWorse)
        #expect(smallBadges.speed == .muchWorse)
        #expect(smallBadges.size == .muchBetter)

        let appleBadges = catalog.badges(for: apple, language: "it")
        #expect(appleBadges.accuracy == .unknown)
        #expect(appleBadges.size == .muchBetter)
    }

    /// In greco Parakeet ha un WER molto più alto: il consigliato cambia con la lingua.
    @Test func recommendationDependsOnTheLanguage() throws {
        #expect(try catalog().recommended(for: "el")?.id == "whisper-large-v3-turbo")
    }

    @Test func modelsWithoutTheLanguageAreNeverRecommendedAndComeLast() throws {
        let catalog = try catalog()
        #expect(catalog.recommended(for: "ja")?.id == "whisper-large-v3-turbo")
        let sorted = catalog.sortedModels(for: "ja")
        #expect(sorted.suffix(2).allSatisfy { !$0.supports("ja") })
    }

    @Test func listsTheUsersLanguagesAModelCannotHandle() throws {
        let catalog = try catalog()
        let ultra = try #require(catalog.model(id: "parakeet-ultra"))
        let missing = catalog.unsupportedLanguages(of: ultra, among: ["it", "ja", "en", "zh"])
        #expect(missing.map(\.code) == ["ja", "zh"])
    }

    @Test func badgeThresholds() {
        #expect(BadgeLevel(ratio: 2) == .muchBetter)
        #expect(BadgeLevel(ratio: 1.2) == .better)
        #expect(BadgeLevel(ratio: 1) == .same)
        #expect(BadgeLevel(ratio: 0.79) == .worse)
        #expect(BadgeLevel(ratio: 0.49) == .muchWorse)
    }
}
