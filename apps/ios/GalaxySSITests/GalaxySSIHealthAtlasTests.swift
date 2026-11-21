import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthAtlasTests: XCTestCase {
  private func catalogue() throws -> GalaxySSIHealthAtlas {
    try GalaxySSIHealthAtlas.load(bundle: Bundle(for: GalaxySSIStore.self), includeArtworkPack: false)
  }

  func testFrozenCatalogueCountsAndCanonicalGraph() throws {
    let atlas = try catalogue()
    XCTAssertEqual(atlas.entries.count, 278)
    XCTAssertEqual(atlas.mechanisms.count, 20)
    XCTAssertEqual(atlas.entries.filter { $0.kind == .system }.count, 14)
    XCTAssertEqual(atlas.entries.filter { $0.kind == .organ }.count, 158)
    XCTAssertEqual(atlas.entries.filter { $0.kind == .cell }.count, 105)
    XCTAssertEqual(atlas.entries.filter { $0.kind == .fragment }.map(\.id), ["fragment-platelet"])
    for entry in atlas.entries {
      XCTAssertTrue(entry.related.allSatisfy { atlas.entry($0) != nil })
      XCTAssertEqual(atlas.model(entry).stages.count, 4)
      XCTAssertEqual(atlas.model(entry).source.host, "openstax.org")
    }
    XCTAssertTrue(atlas.cells(try XCTUnwrap(atlas.entry("cardio"))).contains { $0.id == "cell-cardiomyocyte" })
    XCTAssertTrue(atlas.parents(try XCTUnwrap(atlas.entry("ventricles"))).contains { $0.id == "heart" })
  }

  func testEveryCatalogueKeyResolvesInBothLanguagesWithoutAndroidQuoteDelimiters() throws {
    let atlas = try catalogue()
    let keys = atlas.entries.flatMap { [$0.name, $0.description, $0.aliases] } + atlas.mechanisms.flatMap { [$0.title] + $0.stages }
    for language in ["en", "zh-Hans"] {
      for key in keys {
        let value = GalaxySSIHealthAtlasText.get(key, language)
        XCTAssertNotEqual(value, key, key)
        XCTAssertFalse(value.hasPrefix("\""), key)
      }
    }
    XCTAssertNotEqual(GalaxySSIHealthAtlasText.get("health_atlas_heart_name", "en"),
      GalaxySSIHealthAtlasText.get("health_atlas_heart_name", "zh-Hans"))
  }

  func testSearchUsesAllWordsAndIncludesFragmentsOnlyInCellFilter() throws {
    let atlas = try catalogue()
    XCTAssertTrue(atlas.search("pancreatic beta", kind: .cell, system: "endocrine", language: "en")
      .contains { $0.id == "cell-pancreatic-beta-cell" })
    XCTAssertFalse(atlas.search("", kind: .organ, system: "", language: "en").contains { $0.kind == .cell })
    XCTAssertTrue(atlas.search("platelet", kind: .cell, system: "", language: "en").contains { $0.id == "fragment-platelet" })
    XCTAssertTrue(atlas.search("not-a-real-organ", kind: nil, system: "", language: "en").isEmpty)
  }

  func testMetricAssociationsDoNotInventMissingOrganFunctionReadings() {
    XCTAssertEqual(GalaxySSIHealthAtlasMetrics.forEntry("heart"), [.bloodPressure, .restingHeartRate, .ldl, .hdl, .triglycerides])
    XCTAssertEqual(GalaxySSIHealthAtlasMetrics.forEntry("cell-pancreatic-beta-cell"), [.glucose, .hba1c])
    XCTAssertEqual(GalaxySSIHealthAtlasMetrics.forEntry("fragment-platelet"), [.platelets])
    XCTAssertTrue(GalaxySSIHealthAtlasMetrics.forEntry("brain").isEmpty)
  }

  func testBundledArtworkPackIsAdditiveAndValidatesCoordinates() throws {
    let atlas = try catalogue(), bundle = Bundle(for: GalaxySSIStore.self)
    let extra = GalaxySSIHealthAtlas.Entry(id: "test-structure", kind: .organ, name: "name", description: "description",
      systems: ["urinary"], related: ["nephron"], mechanism: "urinary", aliases: "aliases", color: "", icon: "")
    func pack(x: Double = 0.5, anchor: String = "kidneys") -> GalaxySSIHealthAtlas.ArtworkPack {
      .init(schema: 1, entries: [extra], insertAfter: [extra.id: anchor], relatedAdditions: ["kidneys": [extra.id]],
        plates: [.init(id: "test", asset: "HealthAtlasBody", owner: "kidneys", viewLabel: "health_atlas_illustration",
          entryIDs: [extra.id], aspectRatio: 2.0 / 3.0, markers: [.init(id: extra.id, x: x, y: 0.5)])], english: [:])
    }
    let merged = try pack().applying(to: atlas, bundle: bundle)
    XCTAssertEqual(merged.entries.count, atlas.entries.count + 1)
    XCTAssertEqual(merged.entry("kidneys")?.related.first, extra.id)
    let index = try XCTUnwrap(merged.entries.firstIndex { $0.id == "kidneys" })
    XCTAssertEqual(merged.entries[index + 1].id, extra.id)
    XCTAssertThrowsError(try pack(x: .nan).applying(to: atlas, bundle: bundle))
    XCTAssertThrowsError(try pack(x: 1.1).applying(to: atlas, bundle: bundle))
    XCTAssertThrowsError(try pack(anchor: "missing").applying(to: atlas, bundle: bundle))
    XCTAssertThrowsError(try pack().applying(to: merged, bundle: bundle))
  }

  func testTeachingEquationsAndDefensiveRestoration() {
    var heart = GalaxySSIHealthAtlasSimulation.initial("heart")
    XCTAssertEqual(heart.output, 4.9, accuracy: 0.0001)
    let lung = GalaxySSIHealthAtlasSimulation.initial("lungs")
    XCTAssertEqual(lung.output, 6, accuracy: 0.0001)
    heart.phase = .nan; heart.speed = .infinity; heart.first = -10; heart.second = 1_000
    heart.sanitize("heart")
    XCTAssertEqual(heart.phase, 0); XCTAssertEqual(heart.speed, 1)
    XCTAssertEqual(heart.first, 40); XCTAssertEqual(heart.second, 120)
    heart.phase = 1; XCTAssertEqual(heart.stage, 3)
    var elimination = GalaxySSIHealthAtlasElimination()
    XCTAssertEqual(elimination.percent(at: 0), 100)
    XCTAssertEqual(elimination.percent(at: 8), 25, accuracy: 0.0001)
    elimination.halfLife = .nan; elimination.elapsed = 90; elimination.sanitize()
    XCTAssertEqual(elimination.halfLife, 4); XCTAssertEqual(elimination.elapsed, 48)
  }

  func testCalendarMonthYearWindowsAcrossLeapDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 3, day: 31, hour: 12)))
    XCTAssertEqual(GalaxySSIHealthAtlasWindow.week.days(through: date, calendar: calendar), 7)
    XCTAssertEqual(GalaxySSIHealthAtlasWindow.month.days(through: date, calendar: calendar), 31)
    XCTAssertEqual(GalaxySSIHealthAtlasWindow.year.days(through: date, calendar: calendar), 366)
  }

  func testPublicSelectionRoundTripAndUnknownIDsCannotGrowState() throws {
    let atlas = try catalogue(), first = GalaxySSIHealthAtlasState()
    let heart = try XCTUnwrap(atlas.entry("heart"))
    first.binding(heart).wrappedValue.tab = .simulation
    first.binding(heart).wrappedValue.simulation.phase = 0.5
    let restored = GalaxySSIHealthAtlasState()
    restored.restore(first.serialized, atlas: atlas)
    XCTAssertEqual(restored.binding(heart).wrappedValue.tab, .simulation)
    XCTAssertEqual(restored.binding(heart).wrappedValue.simulation.phase, 0.5)
    XCTAssertFalse(first.serialized.contains("measuredAt"))
    restored.restore(String(repeating: "x", count: 256_001), atlas: atlas)
    XCTAssertEqual(restored.entries.count, 1)
  }

  func testOneUseHandoffIsBoundedOwnerBoundAndExpires() throws {
    let handoff = GalaxySSIHealthAtlasAgentHandoff()
    let token = try XCTUnwrap(handoff.prepare(owner: "a", conversation: "c", prompt: "Public teaching", now: 10))
    XCTAssertNil(handoff.consume(token, owner: "b", conversation: "c", now: 11))
    XCTAssertNil(handoff.consume(token, owner: "a", conversation: "c", now: 11))
    let expired = try XCTUnwrap(handoff.prepare(owner: "a", conversation: "c", prompt: "Public teaching", now: 12))
    XCTAssertNil(handoff.consume(expired, owner: "a", conversation: "c", now: 133))
    let success = try XCTUnwrap(handoff.prepare(owner: "a", conversation: "c", prompt: "Public teaching", now: 140))
    XCTAssertEqual(handoff.consume(success, owner: "a", conversation: "c", now: 141)?.prompt, "Public teaching")
    XCTAssertNil(handoff.consume(success, owner: "a", conversation: "c", now: 141))
    for _ in 0..<8 { XCTAssertNotNil(handoff.prepare(owner: "a", conversation: "c", prompt: "Public", now: 150)) }
    XCTAssertNil(handoff.prepare(owner: "a", conversation: "c", prompt: "Public", now: 150))
    XCTAssertNotNil(handoff.prepare(owner: "a", conversation: "c", prompt: "Public", now: 271))
  }

  func testPublicQuestionCarriesModelLimitsAndSourcesWithoutHealthArchive() throws {
    let atlas = try catalogue(), heart = try XCTUnwrap(atlas.entry("heart"))
    var selection = GalaxySSIHealthAtlasState.Selection()
    selection.research = .drugs
    let question = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: heart, selection: selection, research: true, language: "en")
    XCTAssertTrue(question.contains("single-compartment"))
    XCTAssertTrue(question.contains("25.0"))
    XCTAssertTrue(question.contains("pharmacologyeducation.org"))
    XCTAssertTrue(question.contains("not personal health data"))
    XCTAssertFalse(question.contains("measuredAt"))
  }
}
