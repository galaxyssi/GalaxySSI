import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthAtlasOxygenTests: XCTestCase {
  typealias Oxygen = GalaxySSIHealthAtlasOxygen

  func testHalfSaturationAndZeroPressureAreExact() throws {
    for p50 in [15.0, 26.8, 40.0] {
      XCTAssertEqual(try XCTUnwrap(Oxygen.saturation(pressure: p50, p50: p50)), 0.5)
      XCTAssertEqual(try XCTUnwrap(Oxygen.saturation(pressure: 0, p50: p50)), 0)
      XCTAssertEqual(try XCTUnwrap(Oxygen.amounts(pressure: 0, p50: p50, hemoglobinGramsPerLiter: 150)).total, 0)
    }
  }
  func testContentConvertsGramsPerLiterAndFractionOnlyOnce() throws {
    let half = try XCTUnwrap(Oxygen.amounts(pressure: 26.8, p50: 26.8, hemoglobinGramsPerLiter: 150))
    XCTAssertEqual(half.bound, 10.05, accuracy: 1e-9)
    XCTAssertEqual(half.dissolved, 0.08308, accuracy: 1e-9)
    XCTAssertEqual(half.total, 10.13308, accuracy: 1e-9)
    let defaults = try XCTUnwrap(Oxygen.amounts(pressure: 100, p50: 26.8, hemoglobinGramsPerLiter: 150))
    XCTAssertEqual(100 * (try XCTUnwrap(Oxygen.saturation(pressure: 100, p50: 26.8))), 97.2220233, accuracy: 1e-7)
    XCTAssertEqual(defaults.total, 19.8516267, accuracy: 1e-7)
    let dissolvedOnly = try XCTUnwrap(Oxygen.amounts(pressure: 100, p50: 26.8, hemoglobinGramsPerLiter: 0))
    XCTAssertEqual(dissolvedOnly.bound, 0)
    XCTAssertEqual(dissolvedOnly.total, 0.31, accuracy: 1e-9)
  }
  func testHemoglobinChangesContentNotTheSaturationFraction() throws {
    let baseline = try XCTUnwrap(Oxygen.amounts(pressure: 100, p50: 26.8, hemoglobinGramsPerLiter: 150))
    let half = try XCTUnwrap(Oxygen.amounts(pressure: 100, p50: 26.8, hemoglobinGramsPerLiter: 75))
    XCTAssertEqual(half.bound, baseline.bound / 2, accuracy: 1e-9)
    XCTAssertEqual(half.dissolved, baseline.dissolved)
    XCTAssertLessThan(half.total, baseline.total)
    XCTAssertEqual(baseline.total, baseline.bound + baseline.dissolved)
  }
  func testFixedExponentCurveBoundsAndAffinityDirection() throws {
    for rawP50 in stride(from: 150, through: 400, by: 5) {
      var previous = 0.0
      for pressure in 0...150 {
        let value = try XCTUnwrap(Oxygen.saturation(pressure: Double(pressure), p50: Double(rawP50) / 10))
        XCTAssertTrue(value.isFinite); XCTAssertTrue((0...1).contains(value))
        XCTAssertGreaterThanOrEqual(value, previous)
        previous = value
      }
    }
    XCTAssertLessThan(try XCTUnwrap(Oxygen.saturation(pressure: 100, p50: 40)),
      try XCTUnwrap(Oxygen.saturation(pressure: 100, p50: 26.8)))
    XCTAssertEqual(try XCTUnwrap(Oxygen.saturation(pressure: 40, p50: 40)), 0.5)
  }
  func testInvalidParametersAreRejectedAndExtremeRatiosStayFinite() throws {
    for invalid in [Double.nan, .infinity, -.infinity, -1] {
      XCTAssertNil(Oxygen.saturation(pressure: invalid, p50: 26.8))
      XCTAssertNil(Oxygen.saturation(pressure: 100, p50: invalid))
      XCTAssertNil(Oxygen.amounts(pressure: 100, p50: 26.8, hemoglobinGramsPerLiter: invalid))
    }
    XCTAssertNil(Oxygen.saturation(pressure: 100, p50: 0))
    XCTAssertEqual(try XCTUnwrap(Oxygen.saturation(pressure: .greatestFiniteMagnitude, p50: .leastNonzeroMagnitude)), 1)
    XCTAssertEqual(try XCTUnwrap(Oxygen.saturation(pressure: .leastNonzeroMagnitude, p50: .greatestFiniteMagnitude)), 0)
    XCTAssertTrue(try XCTUnwrap(Oxygen.amounts(pressure: .greatestFiniteMagnitude, p50: 26.8,
      hemoglobinGramsPerLiter: .greatestFiniteMagnitude)).total.isFinite)
  }
  func testSourcesAndLocalizedLimitsRemainExplicit() throws {
    XCTAssertEqual(Oxygen.sources.map(\.absoluteString), [
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC2862600/", "https://pmc.ncbi.nlm.nih.gov/articles/PMC3485568/"
    ])
    let scope = try XCTUnwrap(GalaxySSIHealthAtlasOxygenText.string("model_oxygen_scope", language: "en"))
    XCTAssertTrue(scope.contains("not clinical reference intervals"))
    XCTAssertTrue(scope.contains("Not a pulse-ox reading"))
    XCTAssertTrue(scope.contains("not modeled separately"))
    XCTAssertNotEqual(GalaxySSIHealthAtlasOxygenText.string("model_oxygen", language: "en"),
      GalaxySSIHealthAtlasOxygenText.string("model_oxygen", language: "zh-Hans"))
    XCTAssertNil(GalaxySSIHealthAtlasOxygenText.string("unrelated_key", language: "en"))
  }

  #if GALAXYSSI_ATLAS_PHYSIOLOGY && GALAXYSSI_ATLAS_OXYGEN
  func testSharedModelOwnershipRestorationAndCurveAreScopedToTheTwoEntries() throws {
    typealias Model = GalaxySSIHealthAtlasPhysiology
    let defaults = Model(kind: .oxygen)
    XCTAssertEqual(defaults.input(1), 26.8, accuracy: 1e-9)
    XCTAssertEqual(defaults.kind.unit, "%"); XCTAssertEqual(defaults.kind.axis, 0)
    XCTAssertEqual(defaults.kind.sources, Oxygen.sources)
    XCTAssertEqual(try XCTUnwrap(defaults.resultAt(26.8)), 50, accuracy: 1e-9)
    XCTAssertEqual(defaults.result, 97.2220233, accuracy: 1e-7)
    XCTAssertEqual(defaults.companionValue, 19.8516267, accuracy: 1e-7)
    for id in ["blood", "cell-erythrocyte"] {
      XCTAssertEqual(Model.restore(id, inputs: [100, 268, 150]), defaults)
      XCTAssertNil(Model.restore(id, inputs: [100, 26, 150]))
      XCTAssertNil(Model.restore(id, inputs: [100, 268]))
    }
    for id in ["cell-neutrophil", "cell-platelet", "fragment-platelet", "cell-astrocyte"] { XCTAssertNil(Model.Kind.forEntry(id)) }
    let half = try XCTUnwrap(defaults.changing(2, to: 75))
    XCTAssertEqual(defaults.result, half.result)
    for pressure in 0...150 { XCTAssertEqual(defaults.resultAt(Double(pressure)), half.resultAt(Double(pressure))) }
    XCTAssertNil(Model(kind: .potassium).oxygenAmounts)
  }
  func testPublicContextIncludesComponentsAndBothSourcesWithoutMeasurements() throws {
    let model = GalaxySSIHealthAtlasPhysiology(kind: .oxygen)
    let context = GalaxySSIHealthAtlasPhysiologyText.context(model, language: "en")
    for source in Oxygen.sources { XCTAssertTrue(context.contains(source.absoluteString)) }
    XCTAssertTrue(context.contains("Oxygen partial pressure: 100 mmHg"))
    XCTAssertTrue(context.contains("Hemoglobin concentration: 150 g/L"))
    XCTAssertTrue(context.contains("Bound:")); XCTAssertTrue(context.contains("Dissolved:"))
    XCTAssertTrue(context.contains("Not personal measurements")); XCTAssertFalse(context.contains("measuredAt"))
    XCTAssertNotNil(GalaxySSIHealthAtlasPhysiologyText.processNote(language: "en"))
  }
  #endif
}
