import XCTest
import SwiftUI
@testable import GalaxySSI

final class GalaxySSIHealthAtlasModelComparisonTests: XCTestCase {
  typealias Model = GalaxySSIHealthAtlasModelComparison
  func testDefaultMatchesThePinnedIndependentFourHourFixture() throws {
    let model = Model.standard, point = model.point
    XCTAssertEqual(model.scenario, .exchange); XCTAssertEqual(model.quarterHours, 16); XCTAssertEqual(model.hours, 4)
    XCTAssertEqual(point.two.central, 31.31146654418996, accuracy: 1e-10)
    XCTAssertEqual(point.low, 23.34020536954366, accuracy: 1e-10)
    XCTAssertEqual(point.one, 100 * exp(-0.4), accuracy: 1e-12)
    XCTAssertEqual(point.high, point.one, accuracy: 1e-12)
    XCTAssertEqual(point.centralGap, -35.72053805937397, accuracy: 1e-10)
  }
  func testFrozenPairedScenariosKeepTheSameEliminationAndInitialAmount() throws {
    let pairs = [(0, 0), (30, 15), (100, 40)]
    for scenario in Model.Scenario.allCases {
      let distribution = scenario.distribution, pair = pairs[scenario.rawValue]
      XCTAssertEqual(distribution.outward, pair.0); XCTAssertEqual(distribution.returning, pair.1)
      XCTAssertEqual(distribution.elimination, 10); XCTAssertEqual(distribution.k10, 0.1)
      let first = try XCTUnwrap(Model(scenario: scenario)?.at(0))
      XCTAssertEqual(first.one, 100); XCTAssertEqual(first.two, .init(central: 100, peripheral: 0, eliminated: 0))
      XCTAssertEqual(first.low, 100); XCTAssertEqual(first.high, 100)
    }
  }
  func testAllQuarterHoursConserveAmountShareEnvelopeAndUseTheCachedTrace() throws {
    for quarter in 0...192 {
      let models = try Model.Scenario.allCases.map { try XCTUnwrap(Model(scenario: $0, quarterHours: quarter)) }
      let points = models.map(\.point), low = try XCTUnwrap(points.map(\.two.central).min())
      let high = try XCTUnwrap(points.map(\.two.central).max())
      for (model, point) in zip(models, points) {
        XCTAssertEqual(point.one, points[0].one); XCTAssertEqual(point.low, low); XCTAssertEqual(point.high, high)
        XCTAssertEqual(point.centralGap, point.two.central - point.one)
        XCTAssertEqual(point.two.values.reduce(0, +), 100, accuracy: 1e-10)
        XCTAssertTrue(point.two.values.allSatisfy { $0.isFinite && (0...100).contains($0) })
        XCTAssertTrue((point.low...point.high).contains(point.two.central))
        XCTAssertEqual(model.samples.count, 193); XCTAssertEqual(model.samples[quarter], point)
      }
      XCTAssertEqual(points[0].one, points[0].two.central); XCTAssertEqual(points[0].two.peripheral, 0)
      XCTAssertEqual(points[0].centralGap, 0)
    }
    for invalid in [Double.nan, .infinity, -.infinity, -0.001, 48.001] { XCTAssertNil(Model.standard.at(invalid)) }
    XCTAssertNil(Model(quarterHours: -1)); XCTAssertNil(Model(quarterHours: 193))
    XCTAssertNil(Model(quarterHours: Int.max)); XCTAssertNotNil(Model.standard.at(0.125))
  }
  func testCumulativeValuesMatchThePinnedAugmentedMatrixFixtures() throws {
    let total = Model.standard.centralAmountHours()
    XCTAssertEqual(total.two, 219.6577427940722, accuracy: 1e-10)
    XCTAssertEqual(total.one, 329.6799539643607, accuracy: 1e-10)
    XCTAssertEqual(total.gap, -110.0222111702885, accuracy: 1e-10)
    XCTAssertEqual(try XCTUnwrap(Model(scenario: .faster)).centralAmountHours().two, 148.0005412446694, accuracy: 1e-10)
    XCTAssertEqual(try XCTUnwrap(Model(quarterHours: 0)).centralAmountHours(), .init(one: 0, two: 0))
    for scenario in Model.Scenario.allCases {
      var previous = Model.CentralAmountHours(one: 0, two: 0)
      for quarter in 0...192 {
        let current = try XCTUnwrap(Model(scenario: scenario, quarterHours: quarter)).centralAmountHours()
        XCTAssertGreaterThanOrEqual(current.one, previous.one)
        XCTAssertGreaterThanOrEqual(current.two, previous.two)
        if scenario == .control { XCTAssertEqual(current.gap, 0) }
        previous = current
      }
    }
  }
  func testCumulativeDisclosureRestoresAndLegacySelectionsDefaultToClosed() throws {
    typealias State = GalaxySSIHealthAtlasDrugState
    var old = try XCTUnwrap(State.restore([2, 30, 15, 10, 16, 2, 23]))
    XCTAssertFalse(old.showComparisonTotals)
    XCTAssertFalse(try XCTUnwrap(State.restore([1, 63, 20, 10, 41])).showComparisonTotals)
    old.showComparisonTotals = true
    XCTAssertEqual(State.restore(old.encoded), old)
    XCTAssertEqual(old.encoded, [2, 30, 15, 10, 16, 2, 23, 1])
    for flag in [-1, 2, Int.max] {
      var invalid = old.encoded; invalid[7] = flag
      XCTAssertNil(State.restore(invalid))
    }
  }
  @MainActor func testCumulativeContextIsIncludedOnlyForTheExpandedSelectedComparison() throws {
    let atlas = try GalaxySSIHealthAtlas.load(bundle: Bundle(for: GalaxySSIStore.self))
    let state = GalaxySSIHealthAtlasState(), heart = try XCTUnwrap(atlas.entry("heart"))
    var drugs = GalaxySSIHealthAtlasDrugState(mode: .comparison,
      comparison: try XCTUnwrap(Model(scenario: .faster, quarterHours: 37)), showComparisonTotals: true)
    state.binding(heart).wrappedValue.research = .drugs
    state.binding(heart).wrappedValue.drugInputs = drugs.encoded
    let restored = GalaxySSIHealthAtlasState(); restored.restore(state.serialized, atlas: atlas)
    XCTAssertEqual(GalaxySSIHealthAtlasDrugState.restore(restored.binding(heart).wrappedValue.drugInputs), drugs)
    for language in ["en", "zh-Hans"] {
      func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
      let locale = GalaxySSILocalization.interfaceLocale(language: language)
      let total = GalaxySSIHealthAtlasComparisonText.totals(drugs.comparison, locale: locale, text: t)
      var selection = restored.binding(heart).wrappedValue
      let expanded = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: heart, selection: selection, research: true, language: language)
      XCTAssertTrue(expanded.contains(total)); XCTAssertTrue(expanded.contains(t("compare_total_basis")))
      drugs.showComparisonTotals = false; selection.drugInputs = drugs.encoded
      let collapsed = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: heart, selection: selection, research: true, language: language)
      XCTAssertFalse(collapsed.contains(total)); XCTAssertFalse(collapsed.contains(t("compare_total_basis")))
      for mode in [GalaxySSIHealthAtlasDrugState.Mode.single, .two] {
        var other = drugs; other.mode = mode; other.showComparisonTotals = true; selection.drugInputs = other.encoded
        XCTAssertFalse(GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: heart, selection: selection, research: true, language: language).contains(t("compare_total_basis")))
      }
      drugs.showComparisonTotals = true
    }
  }
  func testLegacyAndExtendedStateRemainIndependentAndRejectMalformedInputs() throws {
    typealias State = GalaxySSIHealthAtlasDrugState
    let distribution = try XCTUnwrap(GalaxySSIHealthAtlasDistribution(outward: 63, returning: 20, elimination: 10, quarterHours: 41))
    let comparison = try XCTUnwrap(Model(scenario: .faster, quarterHours: 23))
    var state = State(mode: .comparison, distribution: distribution, comparison: comparison)
    XCTAssertEqual(state.encoded, [2, 63, 20, 10, 41, 2, 23, 0]); XCTAssertEqual(State.restore(state.encoded), state)
    let legacy = try XCTUnwrap(State.restore([1, 63, 20, 10, 41]))
    XCTAssertEqual(legacy.mode, .two); XCTAssertEqual(legacy.distribution, distribution); XCTAssertEqual(legacy.comparison, .standard)
    XCTAssertEqual(legacy.encoded, [1, 63, 20, 10, 41, 1, 16, 0])
    state.mode = .two; XCTAssertEqual(state.comparison, comparison)
    state.mode = .single; XCTAssertEqual(state.distribution, distribution)
    state.comparison = .standard; XCTAssertEqual(state.distribution, distribution); XCTAssertEqual(state.mode, .single)
    for invalid in [nil, [], [2, 63, 20, 10, 41], [3, 63, 20, 10, 41, 2, 23], [2, 63, 20, 10, 41, 3, 23],
      [2, 63, 20, 10, 41, -1, 23], [2, 63, 20, 10, 41, 2, 193], [2, 301, 20, 10, 41, 2, 23],
      [2, 63, 20, 10, 41, 2, 23, 2], [2, 63, 20, 10, 41, 2, 23, 0, 0]] as [[Int]?] { XCTAssertNil(State.restore(invalid)) }
  }
  @MainActor
  func testComparisonCacheAndQuestionContextStayEntryAndModeScopedInBothLanguages() throws {
    let atlas = try GalaxySSIHealthAtlas.load(bundle: Bundle(for: GalaxySSIStore.self)), state = GalaxySSIHealthAtlasState()
    let heart = try XCTUnwrap(atlas.entry("heart")), liver = try XCTUnwrap(atlas.entry("liver"))
    let comparison = try XCTUnwrap(Model(scenario: .faster, quarterHours: 37))
    let distribution = try XCTUnwrap(GalaxySSIHealthAtlasDistribution(outward: 75))
    let drugs = GalaxySSIHealthAtlasDrugState(mode: .comparison, distribution: distribution, comparison: comparison)
    state.binding(heart).wrappedValue.research = .drugs
    state.binding(heart).wrappedValue.drugInputs = drugs.encoded
    state.binding(heart).wrappedValue.elimination.halfLife = 7
    state.binding(heart).wrappedValue.elimination.elapsed = 21
    XCTAssertNil(state.binding(liver).wrappedValue.drugInputs)
    let restored = GalaxySSIHealthAtlasState(); restored.restore(state.serialized, atlas: atlas)
    XCTAssertEqual(GalaxySSIHealthAtlasDrugState.restore(restored.binding(heart).wrappedValue.drugInputs), drugs)
    XCTAssertEqual(restored.binding(heart).wrappedValue.elimination, state.binding(heart).wrappedValue.elimination)
    for language in ["en", "zh-Hans"] {
      func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
      let locale = GalaxySSILocalization.interfaceLocale(language: language)
      let publicContext = GalaxySSIHealthAtlasComparisonText.context(comparison, locale: locale, text: t)
      var selection = restored.binding(heart).wrappedValue
      let prompt = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: heart, selection: selection, research: true, language: language)
      XCTAssertTrue(prompt.contains(publicContext)); XCTAssertTrue(prompt.contains(t("compare_limit")))
      XCTAssertFalse(prompt.contains(t("elimination_assumptions")))
      XCTAssertFalse(prompt.contains(distribution.context(locale: locale, text: t)))
      XCTAssertFalse(prompt.contains("measuredAt")); XCTAssertFalse(prompt.contains("recordId"))
      for topic in [GalaxySSIHealthAtlasState.Research.physiology, .aging] {
        selection.research = topic
        let excluded = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: heart, selection: selection, research: true, language: language)
        XCTAssertFalse(excluded.contains(GalaxySSIHealthAtlasComparisonText.validationSource.absoluteString))
      }
      selection.research = .drugs
      selection.drugInputs = GalaxySSIHealthAtlasDrugState(mode: .two, distribution: distribution, comparison: comparison).encoded
      XCTAssertFalse(GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: heart, selection: selection, research: true, language: language)
        .contains(GalaxySSIHealthAtlasComparisonText.validationSource.absoluteString))
      selection.drugInputs = GalaxySSIHealthAtlasDrugState(mode: .single, distribution: distribution, comparison: comparison).encoded
      XCTAssertFalse(GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: heart, selection: selection, research: true, language: language).contains(publicContext))
    }
  }
}
